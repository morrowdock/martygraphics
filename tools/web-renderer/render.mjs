#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Prototype, not supported. Renders one settled frame of a MartyGraphics 2D scene (protocol v1) to a PNG with
// headless, muted Chromium. The scene is validated with the Swift rules first; an invalid scene is never drawn.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { PACKAGE_ROOT, ensureBuilt, openRenderer } from "./scripts/browser.mjs";

const USAGE = `Usage: node render.mjs SCENE.json [options]

Validates SCENE.json with the MartyGraphics v1 rules (the Swift parser's checks and
reason codes) and renders one settled board frame to a PNG.

Options:
  --step N        Step to show, 0-based, or "last" (default: the scene's start step, 0).
  --all-steps     Render every step; OUT gets -step<N> before its extension.
  --time T        Seconds of motion and pulse time (default 0).
  --out FILE      PNG to write (default: SCENE name + .png in the current directory).
  --size WxH      Output size in pixels, e.g. 1920x1080 or 1080x1920 (default 1920x1080).
  --scale S       Device pixels per point (default 1). The board is laid out at
                  (W/S) x (H/S) points, as SwiftUI lays out a view of that size.
  --pack NAME     Enable an opt-in template pack (graphs). Repeatable.
  --patch FILE    Apply a v1 patch before rendering. Repeatable, in order.
  --check         Validate only; print the validator outcome as JSON.
  -h, --help      Show this help.

Exit codes: 0 rendered (or valid), 1 refused by validation, 2 usage, 3 unreadable input.`;

function usage(message) {
  if (message) console.error(message);
  console.error(USAGE);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { packs: [], patches: [], size: "1920x1080", scale: 1, time: 0, step: undefined, allSteps: false, check: false };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const value = () => {
      if (i + 1 >= argv.length) usage(`${a} needs a value`);
      return argv[++i];
    };
    if (a === "-h" || a === "--help") {
      console.log(USAGE);
      process.exit(0);
    } else if (a === "--step") opts.step = value();
    else if (a === "--all-steps") opts.allSteps = true;
    else if (a === "--time") opts.time = Number(value());
    else if (a === "--out") opts.out = value();
    else if (a === "--size") opts.size = value();
    else if (a === "--scale") opts.scale = Number(value());
    else if (a === "--pack") opts.packs.push(value());
    else if (a === "--patch") opts.patches.push(value());
    else if (a === "--check") opts.check = true;
    else if (a === "--") rest.push(...argv.slice(i + 1)), (i = argv.length);
    else if (a.startsWith("-")) usage(`unknown option ${a}`);
    else rest.push(a);
  }
  if (rest.length !== 1) usage("give exactly one scene file");
  opts.scenePath = rest[0];
  const m = /^(\d{1,5})x(\d{1,5})$/.exec(opts.size);
  if (!m) usage("--size must look like 1920x1080");
  opts.width = Number(m[1]);
  opts.height = Number(m[2]);
  if (!(opts.width >= 16 && opts.width <= 8192 && opts.height >= 16 && opts.height <= 8192)) usage("--size must be 16..8192 per side");
  if (!(opts.scale > 0 && opts.scale <= 8)) usage("--scale must be in (0, 8]");
  if (!Number.isFinite(opts.time) || opts.time < 0) usage("--time must be a finite number >= 0");
  if (opts.step !== undefined && opts.step !== "last" && !/^\d+$/.test(opts.step)) usage("--step must be a whole number or last");
  if (opts.step !== undefined && opts.allSteps) usage("--step and --all-steps cannot be combined");
  return opts;
}

function readInput(file, limit) {
  try {
    const st = fs.statSync(file);
    if (!st.isFile()) throw new Error("not a regular file");
    if (st.size > limit) return { bytes: null, size: st.size };
    return { bytes: fs.readFileSync(file), size: st.size };
  } catch (e) {
    console.error(`${file}: unreadable: ${e.message}`);
    process.exit(3);
  }
}

const opts = parseArgs(process.argv.slice(2));
ensureBuilt();
const MG = await import(pathToFileURL(path.join(PACKAGE_ROOT, "dist", "index.js")).href);

// 1. Validate in Node with the Swift rules (SceneValidator bounds the raw input first).
const scene = readInput(opts.scenePath, MG.maximumInputBytes);
if (scene.bytes === null) {
  console.log(JSON.stringify({ status: "invalid", reason: "input.too-large" }));
  process.exit(1);
}
const outcome = MG.checkSceneBytes(scene.bytes, { packs: opts.packs });
if (outcome.status !== "valid") {
  console.log(JSON.stringify(outcome));
  process.exit(1);
}
const patches = opts.patches.map((p) => readInput(p, MG.MGLimits.patchBytes * 2).bytes ?? Buffer.alloc(MG.MGLimits.patchBytes * 2 + 1));
let model;
try {
  model = MG.loadScene(scene.bytes, patches, { packs: opts.packs });
} catch (e) {
  console.log(JSON.stringify({ status: "invalid", reason: e.reason ?? String(e) }));
  process.exit(1);
}
if (opts.check) {
  console.log(JSON.stringify({ ...outcome, patched: patches.length > 0, steps: model.steps.length, title: model.title }));
  process.exit(0);
}
if (model.is3D) {
  console.log(JSON.stringify({ status: "invalid", reason: "render.3d.unsupported" }));
  process.exit(1);
}

// 2. Render in headless Chromium with the same code.
const steps = opts.allSteps ? (model.steps.length ? model.steps.map((_, i) => i) : [0]) : [opts.step === undefined ? undefined : opts.step === "last" ? "last" : Number(opts.step)];
const baseOut = opts.out ?? path.basename(opts.scenePath).replace(/\.json$/i, "") + ".png";
const session = await openRenderer();
let status = 0;
try {
  for (const step of steps) {
    const out = opts.allSteps ? baseOut.replace(/(\.png)?$/i, `-step${step}.png`) : baseOut;
    const r = await session.render({
      scene: scene.bytes.toString("utf8"),
      patches: patches.map((p) => p.toString("utf8")),
      packs: opts.packs,
      step,
      time: opts.time,
      width: opts.width / opts.scale,
      height: opts.height / opts.scale,
      scale: opts.scale,
    });
    if (!r.ok) {
      console.log(JSON.stringify({ status: "invalid", reason: r.reason }));
      status = 1;
      break;
    }
    fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
    fs.writeFileSync(out, r.png);
    console.log(JSON.stringify({ status: "rendered", out, step: r.step, steps: r.steps, items: r.items, size: `${opts.width}x${opts.height}`, scale: opts.scale, time: opts.time }));
  }
  if (session.errors.length) {
    console.error(session.errors.join("\n"));
    status = status || 1;
  }
} finally {
  await session.close();
}
process.exit(status);
