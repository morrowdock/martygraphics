// SPDX-License-Identifier: Apache-2.0
// Port of `MGPatch` (Sources/MartyGraphics/MGPatch.swift): a follow-up update to the current scene,
// `{"v":1,"rev":n?,"ops":[...]}` with 1–12 ops. The patch rewrites the scene's source JSON and re-validates the
// WHOLE result; if anything fails the old scene stays (the caller keeps it).

import { fail } from "./errors.js";
import { type JSONObject, type JSONValue, checkEntry, decodeJSONBytes, get, has, jsonEqual, newObject } from "./json.js";
import { MGLimits } from "./limits.js";
import type { MGScene } from "./model.js";
import { parseScene } from "./parser.js";
import { closed, num, objectValue } from "./primitives.js";

export interface MGPatch {
  ops: JSONValue[];
  /** Optional `rev`: the scene revision this patch was written against. */
  baseRevision?: number;
}

const OP_KEYS: Record<string, string[]> = {
  params: ["params"], add: ["item"], remove: ["id"], set: ["id", "key", "value"], steps: ["steps"], step: ["index"],
  camera: ["camera"], title: ["title"], dim: ["dim"],
};

function shape(op: JSONValue): void {
  const o = objectValue(op);
  const name = o ? get(o, "op") : undefined;
  if (!o || typeof name !== "string") fail("patch.op");
  const keys = Object.prototype.hasOwnProperty.call(OP_KEYS, name) ? OP_KEYS[name] : undefined;
  if (!keys) fail(`patch.op.${name}`);
  closed(o, [...keys, "op"], [], `patch.${name}`);
  if (name === "step") {
    const index = num(get(o, "index"), 0, MGLimits.steps - 1, "patch.step");
    if (Math.round(index) !== index) fail("patch.step");
  }
}

/** `MGPatch.parse(data:)`. */
export function parsePatchBytes(bytes: Uint8Array): MGPatch {
  if (bytes.length > MGLimits.patchBytes * 2) fail("patch.json");
  const d = decodeJSONBytes(bytes, "patch.depth", "patch.json");
  if (!d.ok) fail(d.reason);
  return parsePatch(d.value);
}

/** `MGPatch.parse(json:)`. */
export function parsePatch(json: JSONValue): MGPatch {
  const entry = checkEntry(json, MGLimits.depth, MGLimits.patchBytes, { number: "patch.number", depth: "patch.depth", bytes: "patch.object" });
  if (entry) fail(entry);
  const o = objectValue(json);
  if (!o) fail("patch.object");
  closed(o, ["v", "ops"], ["rev"], "patch");
  const ops = get(o, "ops");
  if (get(o, "v") !== 1 || !Array.isArray(ops) || ops.length < 1 || ops.length > 12) fail("patch.ops");
  for (const op of ops) shape(op);
  let base: number | undefined;
  if (has(o, "rev")) {
    const d = num(o["rev"], 0, 1_000_000, "patch.rev");
    if (Math.round(d) !== d) fail("patch.rev");
    base = d;
  }
  return { ops, baseRevision: base };
}

const array = (v: JSONValue | undefined): JSONValue[] => (Array.isArray(v) ? [...v] : []);
const idOf = (v: JSONValue): JSONValue | undefined => (objectValue(v) ? get(v as JSONObject, "id") : undefined);

/** `MGScene.applying(_:)`: the updated scene, or an `MGError` (the caller keeps showing the old scene). */
export function applyPatch(scene: MGScene, patch: MGPatch): MGScene {
  const src = objectValue(scene.source);
  if (!src) fail("patch.source");
  if (patch.baseRevision !== undefined && patch.baseRevision !== scene.revision) fail("patch.stale");
  const root = newObject(Object.keys(src).map((k) => [k, src[k]] as [string, JSONValue]));
  let jump: number | undefined;
  // checkShape
  if (patch.ops.length < 1 || patch.ops.length > 12) fail("patch.ops");
  const entry = checkEntry(newObject([["v", 1], ["ops", patch.ops]]), MGLimits.depth, MGLimits.patchBytes,
    { number: "patch.number", depth: "patch.depth", bytes: "patch.object" });
  if (entry) fail(entry);
  for (const op of patch.ops) shape(op);
  const hasTemplate = scene.template !== undefined;
  const sceneHas = (id: string) => scene.items.some((i) => i.id === id);
  for (const op of patch.ops) {
    const o = objectValue(op)!;
    const name = o["op"] as string;
    switch (name) {
      case "params": {
        const params = objectValue(get(root, "params"));
        const add = objectValue(get(o, "params"));
        if (!hasTemplate || !params || !add) fail("patch.params");
        const merged = newObject(Object.keys(params).map((k) => [k, params[k]] as [string, JSONValue]));
        for (const k of Object.keys(add)) merged[k] = add[k];
        root["params"] = merged;
        break;
      }
      case "add": {
        if (!has(o, "item")) fail("patch.add");
        const list = array(get(root, "items"));
        list.push(o["item"]);
        root["items"] = list;
        break;
      }
      case "remove": {
        const id = get(o, "id");
        if (typeof id !== "string") fail("patch.remove");
        const list = array(get(root, "items"));
        const i = list.findIndex((e) => jsonEqual(idOf(e), id));
        if (i >= 0) {
          list.splice(i, 1);
          if (list.length === 0 && hasTemplate) delete root["items"];
          else root["items"] = list;
        } else if (hasTemplate && sceneHas(id)) {
          const hide = array(get(root, "hide"));
          if (!hide.some((h) => h === id)) hide.push(id);
          root["hide"] = hide;
          const over = array(get(root, "over")).filter((e) => !jsonEqual(idOf(e), id));
          if (over.length === 0) delete root["over"];
          else root["over"] = over;
        } else fail("patch.remove.ref");
        break;
      }
      case "set": {
        const id = get(o, "id");
        const key = get(o, "key");
        if (typeof id !== "string" || typeof key !== "string" || !has(o, "value")) fail("patch.set");
        const value = o["value"];
        const list = array(get(root, "items"));
        const i = list.findIndex((e) => jsonEqual(idOf(e), id));
        const obj = i >= 0 ? objectValue(list[i]) : undefined;
        if (i >= 0 && obj) {
          if (key === "id" || key === "k") fail("patch.set.key");
          const copy = newObject(Object.keys(obj).map((k) => [k, obj[k]] as [string, JSONValue]));
          copy[key] = value;
          if (key === "on") delete copy["from"];
          if (key === "from" && copy["k"] === "vector") delete copy["on"];
          list[i] = copy;
          root["items"] = list;
        } else if (hasTemplate && sceneHas(id)) {
          const over = array(get(root, "over")).filter((e) => {
            const eo = objectValue(e);
            return !(eo && jsonEqual(get(eo, "id"), id) && jsonEqual(get(eo, "key"), key));
          });
          over.push(newObject([["id", id], ["key", key], ["value", value]]));
          root["over"] = over;
        } else fail("patch.set.ref");
        break;
      }
      case "steps":
        root["steps"] = o["steps"];
        break;
      case "step": {
        const d = get(o, "index");
        if (typeof d !== "number" || !Number.isFinite(d) || Math.round(d) !== d || d < 0 || d >= MGLimits.steps) fail("patch.step");
        jump = d;
        break;
      }
      case "camera":
        root["camera"] = o["camera"];
        break;
      case "title":
        root["title"] = o["title"];
        break;
      case "dim":
        root["dim"] = o["dim"];
        break;
      default:
        fail("patch.op");
    }
  }
  const next = parseScene(root, { packs: scene.packs });
  next.revision = scene.revision + 1;
  if (jump !== undefined) {
    if (jump >= Math.max(next.steps.length, 1)) fail("patch.step.range");
    next.startStep = jump;
  }
  return next;
}
