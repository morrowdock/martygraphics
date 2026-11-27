// SPDX-License-Identifier: Apache-2.0
// Shared headless-Chromium session for the CLI, the parity script, the contact sheet and the snapshot tests.
// The page is served from this package through request interception (no server, no network): every request to
// http://localhost:9/ is answered from disk, anything else is aborted. Audio is muted.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const REPO_ROOT = path.resolve(PACKAGE_ROOT, "..", "..");
export const ORIGIN = "http://localhost:9";

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json",
  ".png": "image/png", ".gif": "image/gif", ".css": "text/css" };

/** Files the page may load, relative to the repository root (the package, plus reference images for parity). */
function resolveRequest(url) {
  const u = new URL(url);
  if (u.origin !== ORIGIN) return null;
  const rel = decodeURIComponent(u.pathname).replace(/^\/+/, "");
  const file = path.resolve(REPO_ROOT, rel);
  const allowed = [PACKAGE_ROOT, path.join(REPO_ROOT, "docs", "assets", "native")];
  if (!allowed.some((dir) => file === dir || file.startsWith(dir + path.sep))) return null;
  if (file.includes(`${path.sep}node_modules${path.sep}`)) return null;
  return fs.existsSync(file) && fs.statSync(file).isFile() ? file : null;
}

export function ensureBuilt() {
  const entry = path.join(PACKAGE_ROOT, "dist", "browser.js");
  if (!fs.existsSync(entry)) {
    throw new Error("dist/ is missing: run `npm run build` in tools/web-renderer first");
  }
}

export async function openRenderer({ width = 1280, height = 800 } = {}) {
  ensureBuilt();
  const { chromium } = await import("playwright");
  const browser = await chromium.launch({
    headless: true,
    args: ["--mute-audio", "--force-color-profile=srgb", "--disable-lcd-text", "--hide-scrollbars"],
  });
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  await context.route("**/*", async (route) => {
    const file = resolveRequest(route.request().url());
    if (!file) return route.abort();
    return route.fulfill({ status: 200, body: fs.readFileSync(file), contentType: TYPES[path.extname(file)] ?? "application/octet-stream" });
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(`${ORIGIN}/tools/web-renderer/web/render.html`);
  await page.waitForFunction(() => window.MGWebReady === true, null, { timeout: 20000 }).catch(() => {
    throw new Error(`renderer page did not load: ${errors.join("; ") || "timeout"}`);
  });
  return {
    browser,
    page,
    errors,
    /** Renders one frame in the page. `req` is the browser RenderRequest. Returns { ok, ..., png: Buffer }. */
    async render(req) {
      const r = await page.evaluate((q) => window.MGWeb.render(q), req);
      if (r.ok) r.png = Buffer.from(r.png.slice(r.png.indexOf(",") + 1), "base64");
      return r;
    },
    async close() {
      await browser.close();
    },
  };
}
