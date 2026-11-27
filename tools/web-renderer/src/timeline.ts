// SPDX-License-Identifier: Apache-2.0
// Port of `MGTimeline` (Sources/MartyGraphics/MGTimeline.swift): step state and motion frames as pure functions of
// (scene, step, time), so renderers and tests agree.

import { type MGItem, type MGPoint, type MGScene, P, add, cloneItem, mul, n, sub } from "./model.js";
import { apply } from "./parser.js";
import type { Ctx } from "./primitives.js";

/** Index of the first step that lists each item in `show`. Items never listed are always visible. */
export function firstShown(scene: MGScene): Map<string, number> {
  const out = new Map<string, number>();
  scene.steps.forEach((s, i) => {
    for (const id of s.show) if (!out.has(id)) out.set(id, i);
  });
  return out;
}

/** Items visible at `step` with step edits 0...step applied. A scene without steps shows everything. */
export function itemsAtStep(scene: MGScene, step: number): MGItem[] {
  const ctx: Ctx = { width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values };
  let items = scene.items;
  if (scene.steps.length > 0) {
    const last = Math.min(Math.max(step, 0), scene.steps.length - 1);
    for (const s of scene.steps.slice(0, last + 1)) {
      for (const e of s.edits) {
        try {
          items = apply(e, items, ctx);
        } catch {
          // Swift: `(try? MGParser.apply(e, to: items, ctx)) ?? items`
        }
      }
    }
    const first = firstShown(scene);
    items = items.filter((i) => (first.get(i.id) ?? 0) <= last);
  }
  // A vector, highlight or edge whose anchor is hidden is hidden too, transitively.
  while (true) {
    const ids = new Set(items.map((i) => i.id));
    const kept = items.filter((i) => {
      switch (i.kind) {
        case "vector": return i.ref === undefined || ids.has(i.ref);
        case "highlight": return ids.has(i.ref ?? "");
        case "edge": return ids.has(i.ref ?? "") && ids.has(i.ref2 ?? "");
        default: return true;
      }
    });
    if (kept.length === items.length) return kept;
    items = kept;
  }
}

/** Motion applied at `time` seconds. Vectors with `on` get an absolute tail at their body's current centre. */
export function frame(scene: MGScene, items: MGItem[], time: number): MGItem[] {
  const offsets = new Map<string, MGPoint>();
  const t = Math.max(0, time);
  // Template motion: none of the shipped templates has one (`scene.motion` is always "none" here).
  // Model-written bodies with `move` glide to their target and back (ease in-out), forever.
  for (const i of items) {
    if (i.kind !== "body" || i.pts.length <= 1) continue;
    const period = n(i, "moveT", 1);
    const cycle = (t / period) % 2;
    const x = cycle <= 1 ? cycle : 2 - cycle;
    const ease = x * x * (3 - 2 * x);
    offsets.set(i.id, add(offsets.get(i.id) ?? P(0, 0), mul(sub(i.pts[1], i.pts[0]), ease)));
  }
  const centers = new Map<string, MGPoint>();
  const out = items.map((item) => {
    const i = cloneItem(item);
    const o = offsets.get(i.id);
    if (o && i.pts.length) i.pts[0] = add(i.pts[0], o);
    if (i.kind === "body" && i.pts.length > 1) i.pts.pop(); // the move target is not drawn
    const body = scene.attachments[i.id];
    const bo = body !== undefined ? offsets.get(body) : undefined;
    if (bo && i.pts.length) i.pts[i.pts.length - 1] = add(i.pts[i.pts.length - 1], bo);
    if ((i.kind === "body" || i.kind === "node") && i.pts.length) centers.set(i.id, i.pts[0]);
    return i;
  });
  for (const i of out) {
    if (i.kind === "vector" && i.ref !== undefined) {
      const c = centers.get(i.ref);
      if (c) i.pts = [c];
    }
  }
  return out;
}

/** Damped spring from 0 to 1 over about 0.8 s with a little overshoot (`MGTimeline.spring`). */
export function spring(elapsed: number): number {
  if (!(elapsed < 1.2)) return 1;
  return 1 - Math.exp(-6.5 * elapsed) * Math.cos(8.5 * elapsed);
}

/** Length of one motion loop in seconds, or null when nothing moves (`MGTimeline.cycle`). */
export function cycle(scene: MGScene): number | null {
  const moves = scene.items.map((i) => i.num["moveT"]).filter((v): v is number => v !== undefined);
  return moves.length ? 2 * Math.max(...moves) : null;
}
