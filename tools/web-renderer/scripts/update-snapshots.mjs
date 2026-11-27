// SPDX-License-Identifier: Apache-2.0
// Rewrites test/snapshots from the current renderer (review the PNG changes before committing them).
import { spawnSync } from "node:child_process";
import path from "node:path";
import { PACKAGE_ROOT } from "./browser.mjs";

const r = spawnSync(process.execPath, ["--test", path.join(PACKAGE_ROOT, "test", "render-snapshot.render.test.mjs")], {
  stdio: "inherit",
  env: { ...process.env, UPDATE_SNAPSHOTS: "1" },
});
process.exit(r.status ?? 1);
