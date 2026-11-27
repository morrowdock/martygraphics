// SPDX-License-Identifier: Apache-2.0
// The command-line contract of render.mjs: output size, --scale, --all-steps, --check, --patch and fail-closed
// refusals (exit 1, a JSON reason, nothing written).

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { PACKAGE_ROOT, REPO_ROOT } from "./corpus.mjs";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mg-web-cli-"));
const fixture = (n) => path.join(REPO_ROOT, "docs", "fixtures", "v1", n);
const showcase = (n) => path.join(REPO_ROOT, "Examples", "Showcase", "Sources", "MartyShowcase", "Scenes", n);
const run = (...args) => spawnSync(process.execPath, [path.join(PACKAGE_ROOT, "render.mjs"), ...args], { encoding: "utf8", timeout: 120000 });
const pngSize = (file) => {
  const b = fs.readFileSync(file);
  assert.equal(b.subarray(0, 8).toString("hex"), "89504e470d0a1a0a", "PNG signature");
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
};

test("renders 1920x1080 by default and 1080x1920 on request", () => {
  const a = path.join(tmp, "land.png");
  let r = run(showcase("handoff.json"), "--step", "last", "--out", a);
  assert.equal(r.status, 0, r.stderr + r.stdout);
  assert.deepEqual(pngSize(a), [1920, 1080]);
  assert.equal(JSON.parse(r.stdout.trim()).step, 2);
  const b = path.join(tmp, "port.png");
  r = run(showcase("handoff.json"), "--size", "1080x1920", "--scale", "2", "--out", b);
  assert.equal(r.status, 0, r.stderr + r.stdout);
  assert.deepEqual(pngSize(b), [1080, 1920]);
});

test("--all-steps writes one PNG per step", () => {
  const out = path.join(tmp, "tp.png");
  const r = run(showcase("two-pointers.json"), "--all-steps", "--size", "760x440", "--out", out);
  assert.equal(r.status, 0, r.stderr + r.stdout);
  for (let s = 0; s < 4; s++) assert.deepEqual(pngSize(path.join(tmp, `tp-step${s}.png`)), [760, 440]);
});

test("opt-in packs and patches", () => {
  let r = run(fixture("shortest-path.scene.json"), "--check");
  assert.equal(r.status, 1);
  assert.equal(JSON.parse(r.stdout.trim()).reason, "template.unknown");
  r = run(fixture("shortest-path.scene.json"), "--pack", "graphs", "--patch", fixture("shortest-path-edges.patch.json"), "--check");
  assert.equal(r.status, 0, r.stderr + r.stdout);
  assert.equal(JSON.parse(r.stdout.trim()).patched, true);
  r = run(fixture("shortest-path.scene.json"), "--pack", "graphs", "--patch", fixture("shortest-path-null.patch.json"), "--out", path.join(tmp, "null.png"));
  assert.equal(r.status, 1);
  assert.equal(JSON.parse(r.stdout.trim()).reason, "template.target");
  assert.ok(!fs.existsSync(path.join(tmp, "null.png")));
});

test("invalid scenes are refused with the Swift reason and nothing is drawn", () => {
  for (const [name, reason] of [["highlight-cycle.scene.json", "highlight.cycle"], ["unknown-key.scene.json", "scene.unknown.unknown"], ["title.patch.json", "scene.unknown.ops,rev"]]) {
    const out = path.join(tmp, `${name}.png`);
    const r = run(fixture(name), "--out", out);
    assert.equal(r.status, 1, name);
    assert.equal(JSON.parse(r.stdout.trim()).reason, reason, name);
    assert.ok(!fs.existsSync(out), name);
  }
  const big = path.join(tmp, "big.json");
  fs.writeFileSync(big, Buffer.alloc(16385, 0x20));
  assert.equal(JSON.parse(run(big, "--check").stdout.trim()).reason, "input.too-large");
});

test("usage errors exit 2", () => {
  assert.equal(run().status, 2);
  assert.equal(run(fixture("scene.json"), "--size", "big").status, 2);
  assert.equal(run(fixture("scene.json"), "--step", "-1").status, 2);
});
