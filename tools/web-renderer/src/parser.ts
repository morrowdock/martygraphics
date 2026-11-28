// SPDX-License-Identifier: Apache-2.0
// Port of `MGParser` (Sources/MartyGraphics/MGParser.swift): strict, fail-safe decoder for the scene DSL v1. Every
// object has a closed key set; numbers must be finite and in range; text must be short plain text; ids must be
// unique and every reference must resolve. The prototype rejects unsupported scene features before rendering.

import { MGError, fail } from "./errors.js";
import { format } from "./format.js";
import {
  type JSONObject, type JSONValue, checkEntry, decodeJSONBytes, get, has, isObject, newObject,
} from "./json.js";
import { MGLimits } from "./limits.js";
import {
  type MGCamera, type MGEdit, type MGItem, type MGPoint, type MGScene, type MGStep, KINDS_3D, P,
  isColorRole, isKind, n, newItem,
} from "./model.js";
import { TOP_KEYS, allowedKeys, defaultColor, requiredKeys } from "./parser-tables.js";
import {
  type Ctx, closed, dataPoint, identifier, inRange, num, objectValue, point, range, span, text, vector3,
} from "./primitives.js";
import { type TemplateBuild, buildTemplate, library, validateParams } from "./templates.js";
import "./templates-core.js";
import "./pack-graphs.js";
import { scalarCount } from "./unicode.js";

export interface ParseOptions {
  /** Opt-in template packs to register for this parse (`graphs`). The core built-ins are always available. */
  packs?: readonly string[];
}

// MARK: scene

/** `MGParser.scene(data:)`: bytes in, scene out. Over 16 KiB is `json` (the parser's own bound). */
export function parseSceneBytes(bytes: Uint8Array, opts: ParseOptions = {}): MGScene {
  if (bytes.length > MGLimits.sceneBytes * 2) fail("json");
  const d = decodeJSONBytes(bytes, "scene.depth", "json", "scene.key.duplicate.");
  if (!d.ok) fail(d.reason);
  return parseScene(d.value, opts);
}

/** `MGParser.parseScene`: a decoded JSON value in, a validated scene out. */
export function parseScene(json: JSONValue, opts: ParseOptions = {}): MGScene {
  const packs = opts.packs ?? [];
  const o = objectValue(json);
  if (!o) fail("scene.object");
  const entry = checkEntry(json, MGLimits.depth, MGLimits.sceneBytes, { number: "scene.number", depth: "scene.depth", bytes: "scene.bytes" });
  if (entry) fail(entry);
  if (has(o, "sliders")) fail("web.unsupported.sliders");
  closed(o, ["v"], TOP_KEYS, "scene");
  if (get(o, "v") !== 1) fail("scene.version");
  let is3D: boolean;
  const dim = get(o, "dim");
  if (dim === undefined || dim === "2d") is3D = false;
  else if (dim === "3d") is3D = true;
  else fail("scene.dim");

  let build: TemplateBuild | null = null;
  if (has(o, "template")) {
    const name = o["template"];
    const lib = library(packs);
    if (typeof name !== "string" || !lib.has(name)) fail("template.unknown");
    const template = lib.get(name)!;
    if (has(o, "world")) fail("template.world");
    const p = objectValue(get(o, "params"));
    if (!p) fail("template.params");
    const params = validateParams(template, p);
    const built = buildTemplate(template, params, is3D);
    if (!built) fail("template.build");
    build = built;
  } else {
    for (const key of ["params", "hide", "over"]) if (has(o, key)) fail(`scene.${key}.without.template`);
    if (!has(o, "items")) fail("scene.items.required");
  }

  // Template output gets the same checks as wire input: world size, title, step count and every camera.
  if (build) {
    if (!inRange(build.width, MGLimits.worldMin, MGLimits.worldMax) || !inRange(build.height, MGLimits.worldMin, MGLimits.worldMax)) fail("template.world");
    if (build.steps.length > MGLimits.templateSteps) fail("template.steps");
  }
  let width = build?.width ?? 12;
  let height = build?.height ?? 8;
  if (has(o, "world")) {
    const wo = objectValue(o["world"]);
    if (!wo) fail("world");
    closed(wo, ["w", "h"], [], "world");
    width = num(get(wo, "w"), MGLimits.worldMin, MGLimits.worldMax, "world.w");
    height = num(get(wo, "h"), MGLimits.worldMin, MGLimits.worldMax, "world.h");
  }
  const ctx: Ctx = { width, height, is3D, values: build?.values ?? Object.create(null) };

  // Template output goes through the same item validator as model-written items.
  let items: MGItem[] = (build?.items ?? []).map((i) => item(wire(i), ctx));
  if (has(o, "items")) {
    const raw = o["items"];
    if (!Array.isArray(raw)) fail("items");
    const limit = build ? MGLimits.templateExtras : MGLimits.items;
    const min = build ? 0 : 1;
    if (raw.length < min || raw.length > limit) fail("items.count");
    for (const entry of raw) items.push(item(entry, ctx));
  }
  const ids = new Set<string>();
  for (const i of items) {
    if (ids.has(i.id)) fail(`id.duplicate.${i.id}`);
    ids.add(i.id);
  }

  if (has(o, "hide")) {
    const raw = o["hide"];
    if (!Array.isArray(raw) || raw.length > MGLimits.hide) fail("hide");
    const templateIDs = new Set((build?.items ?? []).map((i) => i.id));
    for (const entry of raw) {
      if (typeof entry !== "string" || !templateIDs.has(entry)) fail("hide.ref");
      items = items.filter((i) => i.id !== entry);
      ids.delete(entry);
    }
  }
  if (has(o, "over")) {
    const raw = o["over"];
    if (!Array.isArray(raw) || raw.length > MGLimits.overrides) fail("over");
    const templateIDs = new Set((build?.items ?? []).map((i) => i.id));
    for (const entry of raw) {
      const e = edit(entry);
      if (!templateIDs.has(e.id)) fail("over.ref");
      items = apply(e, items, ctx);
    }
  }

  // Template walkthroughs skip anything the model hid.
  let steps: MGStep[] = (build?.steps ?? []).map((st) => {
    const s: MGStep = { ...st, show: st.show.filter((id) => ids.has(id)), edits: [...st.edits] };
    s.say = text(st.say, MGLimits.say, ctx, "template.say", false, true);
    if (st.camera) s.camera = camera(cameraWire(st.camera), ctx);
    if (s.focus !== undefined && !ids.has(s.focus)) s.focus = undefined;
    return s;
  });
  if (has(o, "steps")) {
    const raw = o["steps"];
    if (!Array.isArray(raw) || raw.length < 1 || raw.length > MGLimits.steps) fail("steps");
    steps = raw.map((s) => step(s, ctx));
  }
  let title = build ? (build.title === "" ? "" : text(build.title, MGLimits.title, ctx, "template.title")) : "";
  if (has(o, "title")) title = text(o["title"], MGLimits.title, ctx, "title");
  const cam = has(o, "camera") ? camera(o["camera"], ctx) : build?.camera ? camera(cameraWire(build.camera), ctx) : undefined;

  if (items.length > MGLimits.resolvedItems || items.length === 0) fail("items.total");
  if (is3D) for (const i of items) if (!KINDS_3D.has(i.kind)) fail(`3d.kind.${i.kind}`);
  checkReferences(items, steps, ctx);

  return {
    source: json,
    template: typeof o["template"] === "string" ? (o["template"] as string) : undefined,
    title, is3D, width, height, items, steps, camera: cam, values: ctx.values, motion: "none",
    attachments: Object.create(null), startStep: 0, revision: 0, packs: [...packs],
  };
}

export function checkReferences(items: MGItem[], steps: MGStep[], ctx: Ctx): void {
  const byID = new Map(items.map((i) => [i.id, i]));
  checkItemReferences(items);
  let current = items;
  for (const s of steps) {
    for (const id of s.show) if (!byID.has(id)) fail("step.show");
    if (s.focus !== undefined && !byID.has(s.focus)) fail("step.focus");
    for (const e of s.edits) {
      current = apply(e, current, ctx);
      checkItemReferences(current);
    }
  }
}

/** The reference graph, both initially and after each cumulative step edit. */
export function checkItemReferences(items: MGItem[]): void {
  const byID = new Map(items.map((i) => [i.id, i]));
  for (const i of items) {
    switch (i.kind) {
      case "vector":
        if (i.ref !== undefined) {
          const k = byID.get(i.ref)?.kind;
          if (k !== "body" && k !== "node") fail("vector.on");
        }
        break;
      case "highlight":
        if (i.ref === undefined || !byID.has(i.ref) || i.ref === i.id) fail("highlight.target");
        break;
      case "edge":
        if (byID.get(i.ref ?? "")?.kind !== "node" || byID.get(i.ref2 ?? "")?.kind !== "node") fail("edge.nodes");
        break;
      default:
        break;
    }
  }
  // Follow each highlight chain without recursion. A repeated id is a cycle.
  for (const start of items) {
    if (start.kind !== "highlight") continue;
    let current = start;
    const visited = new Set<string>();
    while (current.kind === "highlight") {
      if (visited.has(current.id)) fail("highlight.cycle");
      visited.add(current.id);
      const next = current.ref === undefined ? undefined : byID.get(current.ref);
      if (!next) fail("highlight.target");
      current = next;
    }
  }
}

// MARK: steps, camera, edits

export function step(json: JSONValue, ctx: Ctx): MGStep {
  const o = objectValue(json);
  if (!o) fail("step");
  closed(o, ["say"], ["show", "focus", "cam", "do"], "step");
  const s: MGStep = { say: text(get(o, "say"), MGLimits.say, ctx, "step.say", false, true), show: [], edits: [] };
  if (has(o, "show")) {
    const raw = o["show"];
    if (!Array.isArray(raw) || raw.length > MGLimits.showPerStep) fail("step.show");
    s.show = raw.map((v) => identifier(v, "step.show"));
  }
  if (has(o, "focus")) s.focus = identifier(o["focus"], "step.focus");
  if (has(o, "cam")) s.camera = camera(o["cam"], ctx);
  if (has(o, "do")) {
    const raw = o["do"];
    if (!Array.isArray(raw) || raw.length < 1 || raw.length > MGLimits.stepEdits) fail("step.do");
    s.edits = raw.map(edit);
  }
  return s;
}

export function camera(json: JSONValue | undefined, ctx: Ctx): MGCamera {
  const o = objectValue(json);
  if (!o) fail("camera");
  closed(o, [], ["x", "y", "zoom", "yaw", "pitch"], "camera");
  const c: MGCamera = { zoom: 1, yaw: 25, pitch: 20 };
  if (has(o, "x")) c.x = num(o["x"], 0, ctx.width, "camera.x");
  if (has(o, "y")) c.y = num(o["y"], 0, ctx.height, "camera.y");
  if (has(o, "zoom")) c.zoom = num(o["zoom"], 0.5, 4, "camera.zoom");
  if (has(o, "yaw")) c.yaw = num(o["yaw"], -180, 180, "camera.yaw");
  if (has(o, "pitch")) c.pitch = num(o["pitch"], -89, 89, "camera.pitch");
  return c;
}

export function cameraWire(c: MGCamera): JSONObject {
  const o = newObject([["zoom", c.zoom], ["yaw", c.yaw], ["pitch", c.pitch]]);
  if (c.x !== undefined) o["x"] = c.x;
  if (c.y !== undefined) o["y"] = c.y;
  return o;
}

export function edit(json: JSONValue): MGEdit {
  const o = objectValue(json);
  if (!o) fail("edit");
  closed(o, ["id", "key", "value"], [], "edit");
  const id = identifier(o["id"], "edit.id");
  const key = o["key"];
  if (typeof key !== "string" || key === "id" || key === "k") fail("edit.key");
  return { id, key, value: o["value"] };
}

/** Re-encodes the item, changes one key and re-validates it with the same rules as the wire format. */
export function apply(e: MGEdit, items: MGItem[], ctx: Ctx): MGItem[] {
  const index = items.findIndex((i) => i.id === e.id);
  if (index < 0) fail("edit.ref");
  const target = items[index];
  const w = wire(target);
  if (!allowedKeys(target.kind).has(e.key)) fail(`edit.key.${e.key}`);
  w[e.key] = e.value;
  // Changing one end of an either/or pair removes the other.
  if (e.key === "on") delete w["from"];
  if (e.key === "from" && target.kind === "vector") delete w["on"];
  const out = [...items];
  out[index] = item(w, ctx);
  return out;
}

// MARK: items

export function item(json: JSONValue, ctx: Ctx): MGItem {
  const o = objectValue(json);
  const k = o ? get(o, "k") : undefined;
  if (k === "func" || k === "field" || k === "curve") fail(`web.unsupported.${k}`);
  if (!o || typeof k !== "string" || !isKind(k)) fail("item.kind");
  const kind = k;
  closed(o, [...requiredKeys(kind), "id", "k"], allowedKeys(kind), `item.${k}`);
  const id = identifier(o["id"], "item.id");
  let color = defaultColor(kind);
  if (has(o, "color")) {
    const c = o["color"];
    if (typeof c !== "string" || !isColorRole(c)) fail("item.color");
    color = c;
  }
  const it = newItem(id, kind, color);
  if (has(o, "label")) it.label = text(o["label"], MGLimits.label, ctx, "item.label");
  const sp = span(ctx);
  const p = (key: string) => point(get(o, key), ctx, `${k}.${key}`);
  const req = (key: string, lo: number, hi: number) => num(get(o, key), lo, hi, `${k}.${key}`);
  const opt = (key: string, lo: number, hi: number) => (has(o, key) ? num(o[key], lo, hi, `${k}.${key}`) : undefined);
  const flag = (key: string): boolean => {
    if (!has(o, key)) return false;
    const v = o[key];
    if (typeof v !== "boolean") fail(`${k}.${key}`);
    return v;
  };
  const labels = (prefix: string) => [
    has(o, "xl") ? text(o["xl"], MGLimits.label, ctx, `${prefix}.xl`) : "",
    has(o, "yl") ? text(o["yl"], MGLimits.label, ctx, `${prefix}.yl`) : "",
  ];

  switch (kind) {
    case "body": {
      it.pts = [p("at")];
      const shape = get(o, "shape");
      if (shape === "ball") it.flags.add("ball");
      else if (shape !== undefined && shape !== "box") fail("body.shape");
      it.num["size"] = opt("size", 0.1, sp / 2) ?? 1;
      it.num["angle"] = opt("angle", -360, 360) ?? 0;
      if (has(o, "move")) {
        const mo = objectValue(o["move"]);
        if (!mo) fail("body.move");
        closed(mo, ["to", "t"], [], "body.move");
        it.pts.push(point(get(mo, "to"), ctx, "body.move.to"));
        it.num["moveT"] = num(get(mo, "t"), 0.3, 10, "body.move.t");
      }
      break;
    }
    case "incline":
      it.pts = [p("at")];
      it.num["base"] = req("base", 0.5, ctx.width * 1.25);
      it.num["angle"] = req("angle", 0, 80);
      break;
    case "line": {
      it.pts = [p("from"), p("to")];
      const style = get(o, "style");
      if (style === "dashed") it.flags.add("dashed");
      else if (style === "ground") it.flags.add("ground");
      else if (style !== undefined && style !== "solid") fail("line.style");
      break;
    }
    case "vector": {
      const from = get(o, "from");
      const on = get(o, "on");
      if (from !== undefined && on === undefined) it.pts = [point(from, ctx, "vector.from")];
      else if (from === undefined && on !== undefined) it.ref = identifier(on, "vector.on");
      else fail("vector.anchor");
      if (has(o, "dir")) {
        if (!ctx.is3D || has(o, "angle")) fail("vector.dir");
        it.dir = vector3(o["dir"], "vector.dir");
        it.flags.add("dir3");
      } else {
        it.num["angle"] = req("angle", -360, 360);
      }
      it.num["len"] = req("len", 0, sp);
      if (flag("dashed")) it.flags.add("dashed");
      break;
    }
    case "axes":
      it.pts = [p("at")];
      it.num["w"] = req("w", 0.5, sp * 1.25);
      it.num["h"] = req("h", 0.5, sp * 1.25);
      it.list = labels("axes");
      break;
    case "plot": {
      it.pts = [p("at")];
      it.num["w"] = req("w", 0.5, sp * 1.25);
      it.num["h"] = req("h", 0.5, sp * 1.25);
      const xr = range(get(o, "xr"), "plot.xr");
      const yr = range(get(o, "yr"), "plot.yr");
      it.num["x0"] = xr[0];
      it.num["x1"] = xr[1];
      it.num["y0"] = yr[0];
      it.num["y1"] = yr[1];
      const list = get(o, "pts");
      if (!Array.isArray(list) || list.length < 2 || list.length > MGLimits.points) fail("plot.pts");
      for (const v of list) it.pts.push(dataPoint(v, "plot.pts"));
      it.list = labels("plot");
      break;
    }
    case "spring": {
      it.pts = [p("from"), p("to")];
      const coils = opt("coils", 3, 24) ?? 8;
      if (Math.round(coils) !== coils) fail("spring.coils");
      it.num["coils"] = coils;
      break;
    }
    case "pulley":
      it.pts = [p("at")];
      it.num["r"] = req("r", 0.05, sp / 4);
      break;
    case "rope":
    case "path": {
      const maximum = kind === "rope" ? MGLimits.ropePoints : MGLimits.points;
      const list = get(o, "pts");
      if (!Array.isArray(list) || list.length < 2 || list.length > maximum) fail(`${k}.pts`);
      it.pts = list.map((v) => point(v, ctx, `${k}.pts`));
      if (kind === "path" && flag("dashed")) it.flags.add("dashed");
      break;
    }
    case "orbit":
      it.pts = [p("at")];
      it.num["r"] = req("r", 0.1, sp / 2);
      break;
    case "text": {
      if (get(o, "style") === "math") fail("web.unsupported.text.math");
      it.pts = [p("at")];
      // Text is checked before style, as in Swift, so older invalid documents keep their reason.
      const style = get(o, "style");
      const isCode = style === "code";
      it.text = text(get(o, "text"), MGLimits.text, ctx, "text.text", isCode, true);
      if (style === "callout") it.flags.add("callout");
      else if (style === "title") it.flags.add("title");
      else if (style === "code") {
        if (ctx.is3D) fail("3d.text.code");
        it.flags.add("code");
      } else if (style !== undefined && style !== "label") fail("text.style");
      break;
    }
    case "highlight":
      it.ref = identifier(o["target"], "highlight.target");
      break;
    case "bars": {
      it.pts = [p("at")];
      it.num["w"] = req("w", 0.5, sp * 1.25);
      it.num["h"] = req("h", 0.5, sp * 1.25);
      const list = get(o, "bars");
      if (!Array.isArray(list) || list.length < 1 || list.length > MGLimits.bars) fail("bars.bars");
      it.bars = list.map((b) => {
        const bo = objectValue(b);
        if (!bo) fail("bars.bar");
        closed(bo, ["label", "value"], ["color"], "bars.bar");
        let role: ReturnType<typeof defaultColor> = "energy";
        if (has(bo, "color")) {
          const c = bo["color"];
          if (typeof c !== "string" || !isColorRole(c)) fail("bars.color");
          role = c;
        }
        const label = text(get(bo, "label"), MGLimits.barLabel, ctx, "bars.label");
        const value = num(get(bo, "value"), -1e7, 1e7, "bars.value");
        return { label, value, color: role };
      });
      if (has(o, "unit")) it.text = text(o["unit"], 8, ctx, "bars.unit");
      break;
    }
    case "array": {
      it.pts = [p("at")];
      const list = get(o, "vals");
      if (!Array.isArray(list) || list.length < 1 || list.length > MGLimits.cells) fail("array.vals");
      it.list = list.map((v) => {
        if (typeof v === "number") {
          // A number is stored as its displayed text, so that text obeys the string-cell limit too.
          if (!(Math.abs(v) < 1e6)) fail("array.val");
          const shown = format(v, "");
          if (scalarCount(shown) > MGLimits.cellText) fail("array.val");
          return shown;
        }
        if (typeof v === "string") return text(v, MGLimits.cellText, ctx, "array.val");
        return fail("array.val");
      });
      it.num["cell"] = opt("cell", 0.3, sp / 4) ?? Math.min(1, sp / 4);
      if (has(o, "ptrs")) {
        const ps = o["ptrs"];
        if (!Array.isArray(ps) || ps.length > MGLimits.pointers) fail("array.ptrs");
        it.pointers = ps.map((pv) => {
          const po = objectValue(pv);
          if (!po) fail("array.ptr");
          closed(po, ["i", "label"], [], "array.ptr");
          const i = num(get(po, "i"), 0, list.length - 1, "array.ptr.i");
          if (Math.round(i) !== i) fail("array.ptr.i");
          return { index: i, label: text(get(po, "label"), MGLimits.nodeText, ctx, "array.ptr.label") };
        });
      }
      if (has(o, "marked")) {
        const ms = o["marked"];
        if (!Array.isArray(ms) || ms.length > MGLimits.cells) fail("array.marked");
        it.marked = ms.map((m) => {
          const i = num(m, 0, list.length - 1, "array.marked");
          if (Math.round(i) !== i) fail("array.marked");
          return i;
        });
      }
      break;
    }
    case "node":
      it.pts = [p("at")];
      it.text = text(get(o, "text"), MGLimits.nodeText, ctx, "node.text");
      it.num["r"] = opt("r", 0.2, sp / 6) ?? Math.min(0.5, sp / 6);
      break;
    case "edge":
      it.ref = identifier(o["a"], "edge.a");
      it.ref2 = identifier(o["b"], "edge.b");
      if (it.ref === it.ref2) fail("edge.self");
      if (flag("dir")) it.flags.add("dir");
      break;
    case "table": {
      it.pts = [p("at")];
      const rows = get(o, "cells");
      if (!Array.isArray(rows) || rows.length < 1 || rows.length > MGLimits.tableRows) fail("table.cells");
      let cols = 0;
      for (const row of rows) {
        if (!Array.isArray(row) || row.length < 1 || row.length > MGLimits.tableCols || (cols !== 0 && row.length !== cols)) fail("table.cells");
        cols = row.length;
        for (const v of row) {
          if (typeof v === "number") {
            if (!(Math.abs(v) < 1e6)) fail("table.cell");
            const shown = format(v, "");
            if (scalarCount(shown) > MGLimits.tableCellText) fail("table.cell");
            it.list.push(shown);
          } else if (v === "") {
            it.list.push("");
          } else if (typeof v === "string") {
            it.list.push(text(v, MGLimits.tableCellText, ctx, "table.cell"));
          } else {
            fail("table.cell");
          }
        }
      }
      it.num["rows"] = rows.length;
      it.num["cols"] = cols;
      it.num["cw"] = opt("cw", 0.3, sp / 3) ?? Math.min(1.6, sp / 3);
      it.num["rh"] = opt("rh", 0.3, sp / 6) ?? Math.min(0.7, sp / 6);
      if (flag("header")) it.flags.add("header");
      if (has(o, "marked")) {
        const ms = o["marked"];
        if (!Array.isArray(ms) || ms.length > rows.length * cols) fail("table.marked");
        it.marked = ms.map((m) => {
          if (!Array.isArray(m) || m.length !== 2) fail("table.marked");
          const r = num(m[0], 0, rows.length - 1, "table.marked");
          const c = num(m[1], 0, cols - 1, "table.marked");
          if (Math.round(r) !== r || Math.round(c) !== c) fail("table.marked");
          return r * cols + c;
        });
      }
      break;
    }
    case "region": {
      const list = get(o, "pts");
      if (!Array.isArray(list) || list.length < 3 || list.length > MGLimits.points) fail("region.pts");
      it.pts = list.map((v) => point(v, ctx, "region.pts"));
      if (flag("dashed")) it.flags.add("dashed");
      break;
    }
  }
  return it;
}

// MARK: wire form

/** Wire form of a resolved item (placeholders already filled). Used by edits and patches (`MGItem.wire()`). */
export function wire(i: MGItem): JSONObject {
  const at = (k: number): MGPoint => i.pts[k] ?? P(NaN, NaN);
  const o = newObject([["id", i.id], ["k", i.kind], ["color", i.color]]);
  const pt = (q: MGPoint, z = false): JSONValue => (z || q.z !== 0 ? [q.x, q.y, q.z] : [q.x, q.y]);
  const put = (key: string, numKey?: string) => {
    const v = i.num[numKey ?? key];
    if (v !== undefined) o[key] = v;
  };
  if (i.label !== undefined) o["label"] = i.label;
  const axisLabels = () => {
    if (i.list.length === 2) {
      if (i.list[0] !== "") o["xl"] = i.list[0];
      if (i.list[1] !== "") o["yl"] = i.list[1];
    }
  };
  switch (i.kind) {
    case "body":
      o["at"] = pt(at(0));
      if (i.flags.has("ball")) o["shape"] = "ball";
      put("size");
      put("angle");
      if (i.pts.length > 1 && i.num["moveT"] !== undefined) o["move"] = newObject([["to", pt(at(1))], ["t", i.num["moveT"]]]);
      break;
    case "incline":
      o["at"] = pt(at(0));
      put("base");
      put("angle");
      break;
    case "line":
      o["from"] = pt(at(0));
      o["to"] = pt(at(1));
      if (i.flags.has("dashed")) o["style"] = "dashed";
      if (i.flags.has("ground")) o["style"] = "ground";
      break;
    case "vector":
      if (i.ref !== undefined) o["on"] = i.ref;
      else if (i.pts.length > 0) o["from"] = pt(i.pts[0]);
      if (i.dir) o["dir"] = [i.dir.x, i.dir.y, i.dir.z];
      else put("angle");
      put("len");
      if (i.flags.has("dashed")) o["dashed"] = true;
      break;
    case "axes":
      o["at"] = pt(at(0));
      put("w");
      put("h");
      axisLabels();
      break;
    case "plot":
      o["at"] = pt(at(0));
      put("w");
      put("h");
      o["xr"] = [n(i, "x0"), n(i, "x1")];
      o["yr"] = [n(i, "y0"), n(i, "y1")];
      o["pts"] = i.pts.slice(1).map((q) => [q.x, q.y]);
      axisLabels();
      break;
    case "spring":
      o["from"] = pt(at(0));
      o["to"] = pt(at(1));
      put("coils");
      break;
    case "pulley":
    case "orbit":
      o["at"] = pt(at(0));
      put("r");
      break;
    case "rope":
      o["pts"] = i.pts.map((q) => pt(q));
      break;
    case "path":
      o["pts"] = i.pts.map((q) => pt(q));
      if (i.flags.has("dashed")) o["dashed"] = true;
      break;
    case "text":
      o["at"] = pt(at(0));
      o["text"] = i.text ?? "";
      if (i.flags.has("callout")) o["style"] = "callout";
      if (i.flags.has("title")) o["style"] = "title";
      if (i.flags.has("code")) o["style"] = "code";
      break;
    case "highlight":
      o["target"] = i.ref ?? "";
      break;
    case "bars":
      o["at"] = pt(at(0));
      put("w");
      put("h");
      if (i.text !== undefined) o["unit"] = i.text;
      o["bars"] = i.bars.map((b) => newObject([["label", b.label], ["value", b.value], ["color", b.color]]));
      break;
    case "array":
      o["at"] = pt(at(0));
      o["vals"] = [...i.list];
      put("cell");
      if (i.pointers.length) o["ptrs"] = i.pointers.map((q) => newObject([["i", Math.round(q.index)], ["label", q.label]]));
      if (i.marked.length) o["marked"] = [...i.marked];
      break;
    case "node":
      o["at"] = pt(at(0));
      o["text"] = i.text ?? "";
      put("r");
      break;
    case "edge":
      o["a"] = i.ref ?? "";
      o["b"] = i.ref2 ?? "";
      if (i.flags.has("dir")) o["dir"] = true;
      break;
    case "table": {
      o["at"] = pt(at(0));
      put("cw");
      put("rh");
      const rawCols = n(i, "cols", 1);
      const rawRows = n(i, "rows", 1);
      if (!Number.isFinite(rawCols) || !Number.isFinite(rawRows) || Math.round(rawCols) !== rawCols || Math.round(rawRows) !== rawRows ||
        rawCols < 1 || rawCols > MGLimits.tableCols || rawRows < 1 || rawRows > MGLimits.tableRows || i.list.length !== rawCols * rawRows) {
        o["cells"] = null;
        break;
      }
      const cols = rawCols;
      const cells: JSONValue[] = [];
      for (let r = 0; r < i.list.length; r += cols) cells.push(i.list.slice(r, r + cols));
      o["cells"] = cells;
      if (i.flags.has("header")) o["header"] = true;
      if (i.marked.length) o["marked"] = i.marked.map((m) => [Math.trunc(m / cols), m % cols]);
      break;
    }
    case "region":
      o["pts"] = i.pts.map((q) => pt(q));
      if (i.flags.has("dashed")) o["dashed"] = true;
      break;
  }
  return o;
}

/** Wraps a thrown `MGError` as a reason string (for callers that want a result instead of an exception). */
export function reasonOf(fn: () => unknown): string | null {
  try {
    fn();
    return null;
  } catch (e) {
    if (e instanceof MGError) return e.reason;
    throw e;
  }
}

export { isObject };
