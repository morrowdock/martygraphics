// SPDX-License-Identifier: Apache-2.0
// Browser entry point: validates scene bytes with the Swift rules and draws one settled frame into a canvas.
// The CLI (render.mjs) loads web/render.html, which calls `MGWeb.render` through Playwright.

import { MGError } from "./errors.js";
import { type FrameOptions, loadScene, prepareFrame } from "./frame.js";
import { setShadowBlurPerRadius } from "./gfx.js";
import { draw } from "./renderer.js";

export interface RenderRequest extends FrameOptions {
  /** Scene JSON text (UTF-8 is re-encoded from the string, so pass the file text unchanged). */
  scene: string;
  /** Patch JSON texts applied in order before rendering. */
  patches?: string[];
  /** Opt-in template packs (`graphs`). */
  packs?: string[];
  /** Device pixels per point. The PNG is width*scale × height*scale. */
  scale?: number;
  /** Overrides the shadow calibration (canvas blur per SwiftUI shadow radius). */
  shadowBlurPerRadius?: number;
}

export type RenderResult =
  | { ok: true; step: number; steps: number; title: string; items: number; template: string | null }
  | { ok: false; reason: string };

const encoder = new TextEncoder();

export function render(canvas: HTMLCanvasElement, req: RenderRequest): RenderResult {
  try {
    if (req.shadowBlurPerRadius !== undefined) setShadowBlurPerRadius(req.shadowBlurPerRadius);
    const scene = loadScene(encoder.encode(req.scene), (req.patches ?? []).map((p) => encoder.encode(p)), { packs: req.packs ?? [] });
    const prepared = prepareFrame(scene, req);
    const scale = req.scale ?? 1;
    canvas.width = Math.round(req.width * scale);
    canvas.height = Math.round(req.height * scale);
    const ctx = canvas.getContext("2d")!;
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    draw(prepared.input, ctx, scale);
    return { ok: true, step: prepared.step, steps: scene.steps.length, title: scene.title, items: prepared.input.items.length, template: scene.template ?? null };
  } catch (e) {
    if (e instanceof MGError) return { ok: false, reason: e.reason };
    return { ok: false, reason: `render.error: ${(e as Error)?.message ?? String(e)}` };
  }
}

export * from "./index.js";
