// SPDX-License-Identifier: Apache-2.0
// Test helpers: the compiled package (run `npm run build` first; `npm test` does) and outcome adapters.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { PACKAGE_ROOT } from "./corpus.mjs";

const entry = path.join(PACKAGE_ROOT, "dist", "index.js");
if (!fs.existsSync(entry)) throw new Error("dist/ is missing: run `npm run build` first");
export const MG = await import(pathToFileURL(entry).href);

/** The TypeScript outcome for a corpus case at its Swift entry point: "accept" or the reason code. */
export function swiftOutcome(c) {
  const packs = c.packs ?? [];
  if (c.entry === "parser") {
    try {
      MG.parseSceneBytes(c.bytes, { packs });
      return "accept";
    } catch (e) {
      if (e?.reason) return e.reason;
      throw e;
    }
  }
  const o = MG.checkSceneBytes(c.bytes, { packs });
  return o.status === "valid" ? "accept" : o.reason;
}
