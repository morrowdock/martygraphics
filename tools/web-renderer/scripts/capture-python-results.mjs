// SPDX-License-Identifier: Apache-2.0
// Captures the Python draft preflight's verdict for every corpus input into test/expected/python-checker.json, so the
// parity test runs without Python. The checker lives on the unmerged branch feat/scene-v1-json-schema; point
// MG_SCENE_CHECKER at its tools/scene_v1_check.py (default: the local clone used for this prototype).
//
//   MG_SCENE_CHECKER=/path/to/tools/scene_v1_check.py node scripts/capture-python-results.mjs

import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { PACKAGE_ROOT, corpus } from "../test/corpus.mjs";

const checker = process.env.MG_SCENE_CHECKER ?? "D:/work/mg-scene-schema-20261126/tools/scene_v1_check.py";
const python = process.env.PYTHON ?? "python";
if (!fs.existsSync(checker)) {
  console.error(`checker not found: ${checker} (set MG_SCENE_CHECKER)`);
  process.exit(2);
}
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mg-python-corpus-"));
try {
  const cases = corpus();
  const manifest = cases.map((c, i) => {
    const file = path.join(dir, `${i}.json`);
    fs.writeFileSync(file, c.bytes);
    return { name: c.name, file, packs: c.packs ?? [] };
  });
  const manifestPath = path.join(dir, "manifest.json");
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  const driver = path.join(PACKAGE_ROOT, "scripts", "python_checker_driver.py");
  const results = JSON.parse(execFileSync(python, ["-I", driver, checker, manifestPath], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }));
  const repo = path.resolve(path.dirname(checker), "..");
  let commit = "unknown";
  try {
    commit = execFileSync("git", ["-C", repo, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  } catch {}
  const out = {
    checker: {
      path: "tools/scene_v1_check.py on branch feat/scene-v1-json-schema",
      commit,
      sha256: sha256(fs.readFileSync(checker)),
      schemaSha256: sha256(fs.readFileSync(path.join(repo, "docs", "schemas", "scene-v1.draft.schema.json"))),
      python: execFileSync(python, ["-I", "-c", "import sys; print(sys.version.split()[0])"], { encoding: "utf8" }).trim(),
      platform: `${os.platform()} ${os.release()}`,
    },
    note: "Python draft preflight verdicts per corpus case. pass-deferred: a template scene whose expansion the checker leaves to Swift.",
    results: Object.fromEntries(cases.map((c) => [c.name, { sha256: sha256(c.bytes), ...results[c.name] }])),
  };
  const target = path.join(PACKAGE_ROOT, "test", "expected", "python-checker.json");
  fs.writeFileSync(target, JSON.stringify(out, null, 1) + "\n");
  const counts = {};
  for (const r of Object.values(out.results)) counts[r.status] = (counts[r.status] ?? 0) + 1;
  console.log(`wrote ${target}: ${cases.length} inputs`, counts);
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
