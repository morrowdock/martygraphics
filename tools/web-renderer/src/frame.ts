// SPDX-License-Identifier: Apache-2.0
// One settled board frame, the way `MartyGraphicsView` composes it for a step that has finished its transitions:
// step edits and visibility (`MGTimeline.items`), motion at `time` (`MGTimeline.frame`), the step camera (or the
// scene camera), the step focus, no draw-on in progress.

import { MGError } from "./errors.js";
import { Viewport } from "./layout.js";
import type { MGScene } from "./model.js";
import { applyPatch, parsePatchBytes } from "./patch.js";
import { type ParseOptions, parseSceneBytes } from "./parser.js";
import type { RenderInput } from "./renderer.js";
import { frame, itemsAtStep } from "./timeline.js";

export interface FrameOptions {
  /** Step index, 0-based; "last" for the final step. Default: the scene's start step (0 unless a patch jumped). */
  step?: number | "last";
  /** Seconds since the board appeared (motion, highlight and focus pulses). Default 0. */
  time?: number;
  /** Board size in points. */
  width: number;
  height: number;
}

export interface Prepared {
  scene: MGScene;
  step: number;
  input: RenderInput;
}

/** Parses scene bytes (and optional patch bytes, applied in order) with the Swift rules. Throws `MGError`. */
export function loadScene(sceneBytes: Uint8Array, patches: Uint8Array[] = [], opts: ParseOptions = {}): MGScene {
  let scene = parseSceneBytes(sceneBytes, opts);
  for (const p of patches) scene = applyPatch(scene, parsePatchBytes(p));
  return scene;
}

export function resolveStep(scene: MGScene, step: number | "last" | undefined): number {
  if (scene.steps.length === 0) return 0;
  if (step === undefined) return Math.min(scene.startStep, scene.steps.length - 1);
  if (step === "last") return scene.steps.length - 1;
  if (!Number.isInteger(step) || step < 0 || step >= scene.steps.length) throw new MGError("render.step.range");
  return step;
}

export function prepareFrame(scene: MGScene, opts: FrameOptions): Prepared {
  if (scene.is3D) throw new MGError("render.3d.unsupported");
  const step = resolveStep(scene, opts.step);
  const time = opts.time ?? 0;
  const items = frame(scene, itemsAtStep(scene, step), time);
  const current = scene.steps[step];
  const camera = current?.camera ?? scene.camera;
  const viewport = Viewport.fit({ width: opts.width, height: opts.height }, scene.width, scene.height, camera);
  return { scene, step, input: { scene, items, viewport, focus: current?.focus, time } };
}
