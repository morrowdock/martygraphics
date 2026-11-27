// SPDX-License-Identifier: Apache-2.0
// Port of `SceneValidator.check(data:)` (tools/SceneValidator/Sources/SceneValidatorCore/SceneValidator.swift): the
// raw input bound (`input.too-large`) and then `MGParser.scene(data:)`, unchanged.

import { MGError } from "./errors.js";
import { maximumInputBytes } from "./limits.js";
import { type ParseOptions, parseSceneBytes } from "./parser.js";

export type Outcome =
  | { status: "valid"; dimension: "2d" | "3d"; items: number; steps: number; template: string | null }
  | { status: "invalid"; reason: string };

export function checkSceneBytes(bytes: Uint8Array, opts: ParseOptions = {}): Outcome {
  if (bytes.length > maximumInputBytes) return { status: "invalid", reason: "input.too-large" };
  try {
    const scene = parseSceneBytes(bytes, opts);
    return { status: "valid", dimension: scene.is3D ? "3d" : "2d", items: scene.items.length, steps: scene.steps.length, template: scene.template ?? null };
  } catch (e) {
    if (e instanceof MGError) return { status: "invalid", reason: e.reason };
    return { status: "invalid", reason: "unknown" };
  }
}
