// SPDX-License-Identifier: Apache-2.0
// Page-side pixel helpers for the parity script and the snapshot tests: decode PNG/GIF (via ImageDecoder), find the
// board inside a Showcase card capture, and compare two RGBA images with tolerant, structure-aware metrics.

const BOARD_TOP = [17, 26, 51];
const BOARD_BOTTOM = [10, 15, 31];

function canvasFor(w, h) {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  return c;
}

async function fetchBytes(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

/** All frames of an image (one for PNG) as ImageData. */
export async function decodeFrames(url) {
  const bytes = await fetchBytes(url);
  const type = url.endsWith(".gif") ? "image/gif" : "image/png";
  const decoder = new ImageDecoder({ data: bytes, type });
  await decoder.tracks.ready;
  const count = decoder.tracks.selectedTrack.frameCount;
  const frames = [];
  for (let i = 0; i < count; i++) {
    const { image } = await decoder.decode({ frameIndex: i, completeFramesOnly: true });
    const c = canvasFor(image.displayWidth, image.displayHeight);
    const ctx = c.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(image, 0, 0);
    frames.push(ctx.getImageData(0, 0, c.width, c.height));
    image.close();
  }
  decoder.close();
  return frames;
}

export async function decodePNGBase64(b64) {
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const decoder = new ImageDecoder({ data: bytes, type: "image/png" });
  const { image } = await decoder.decode({ frameIndex: 0 });
  const c = canvasFor(image.displayWidth, image.displayHeight);
  const ctx = c.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(image, 0, 0);
  image.close();
  decoder.close();
  return ctx.getImageData(0, 0, c.width, c.height);
}

const px = (img, x, y) => {
  const i = (y * img.width + x) * 4;
  return [img.data[i], img.data[i + 1], img.data[i + 2]];
};

/**
 * Finds the 760×440 board inside an 840×662 Showcase card capture: the first row (down the card's centre column)
 * whose colour is the board's top gradient colour, and the first column (along a row near the board top) that is.
 * Uses the background only, never the drawn content.
 */
export function findBoard(img, w, h) {
  const near = (c, ref, tol) => Math.abs(c[0] - ref[0]) <= tol && Math.abs(c[1] - ref[1]) <= tol && Math.abs(c[2] - ref[2]) <= tol;
  const cx = Math.floor(img.width / 2);
  let y0 = -1;
  for (let y = 40; y < img.height - h; y++) {
    if (near(px(img, cx, y), BOARD_TOP, 4) && near(px(img, cx, y + 2), BOARD_TOP, 5)) {
      y0 = y;
      break;
    }
  }
  if (y0 < 0) return null;
  let x0 = -1;
  for (let x = 0; x < img.width - w; x++) {
    if (near(px(img, x, y0 + 30), BOARD_TOP, 6) && near(px(img, x + 2, y0 + 30), BOARD_TOP, 6)) {
      x0 = x;
      break;
    }
  }
  if (x0 < 0) return null;
  return { x: x0, y: y0 };
}

/**
 * All w×h boards whose centre column is one of `columns` (the Showcase overview lays out two columns of cards). A board
 * top is a row of the board's top gradient colour below a row that is not; the left edge is found on a row 30 px
 * below it. Returns the boards sorted top to bottom, then left to right.
 */
export function findBoards(img, w, h, columns) {
  const near = (c, ref, tol) => Math.abs(c[0] - ref[0]) <= tol && Math.abs(c[1] - ref[1]) <= tol && Math.abs(c[2] - ref[2]) <= tol;
  const boards = [];
  for (const cx of columns) {
    for (let y = 1; y < img.height - h; y++) {
      if (!near(px(img, cx, y), BOARD_TOP, 4) || !near(px(img, cx, y + 2), BOARD_TOP, 5) || near(px(img, cx, y - 1), BOARD_TOP, 4)) continue;
      let x0 = -1;
      for (let x = Math.max(0, cx - Math.floor(w / 2) - 24); x < cx; x++) {
        if (near(px(img, x, y + 30), BOARD_TOP, 6) && near(px(img, x + 2, y + 30), BOARD_TOP, 6)) {
          x0 = x;
          break;
        }
      }
      if (x0 >= 0) boards.push({ x: x0, y });
      y += h;
    }
  }
  return boards.sort((a, b) => a.y - b.y || a.x - b.x);
}

export function crop(img, x, y, w, h) {
  const c = canvasFor(img.width, img.height);
  const ctx = c.getContext("2d", { willReadFrequently: true });
  ctx.putImageData(img, 0, 0);
  return ctx.getImageData(x, y, w, h);
}

/** Inside the board's rounded clip (corner radius r) — the Showcase card clips the board to a rounded rectangle. */
function insideRounded(x, y, w, h, r) {
  const dx = x < r ? r - x : x > w - 1 - r ? x - (w - 1 - r) : 0;
  const dy = y < r ? r - y : y > h - 1 - r ? y - (h - 1 - r) : 0;
  return dx * dx + dy * dy <= r * r;
}

function background(y, h) {
  const t = h > 1 ? y / (h - 1) : 0;
  return [0, 1, 2].map((k) => BOARD_TOP[k] + (BOARD_BOTTOM[k] - BOARD_TOP[k]) * t);
}

/** Pixels that stand out from the board's own gradient (drawn content), as a mask. */
function foreground(img, threshold) {
  const { width: w, height: h, data } = img;
  const mask = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    const bg = background(y, h);
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const d = Math.max(Math.abs(data[i] - bg[0]), Math.abs(data[i + 1] - bg[1]), Math.abs(data[i + 2] - bg[2]));
      if (d > threshold && insideRounded(x, y, w, h, 16)) mask[y * w + x] = 1;
    }
  }
  return mask;
}

function dilate(mask, w, h, r) {
  const out = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!mask[y * w + x]) continue;
      for (let dy = -r; dy <= r; dy++) {
        const yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (let dx = -r; dx <= r; dx++) {
          const xx = x + dx;
          if (xx >= 0 && xx < w) out[yy * w + xx] = 1;
        }
      }
    }
  }
  return out;
}

/** Palette colours used for the per-colour geometry check (hex from MGTheme.board). */
const PALETTE = {
  blue: [0x5b, 0x8c, 0xff], purple: [0xb3, 0x88, 0xff], teal: [0x2d, 0xd4, 0xbf], yellow: [0xff, 0xe0, 0x66],
  good: [0x69, 0xf0, 0xae], warn: [0xff, 0xb7, 0x4d], accent: [0x7c, 0x9c, 0xff], muted: [0x8a, 0x94, 0xb8],
  ink: [0xee, 0xf2, 0xff],
};

function colorStats(img, rgb, tol) {
  const { width: w, height: h, data } = img;
  let count = 0, sx = 0, sy = 0, minx = w, miny = h, maxx = -1, maxy = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!insideRounded(x, y, w, h, 16)) continue;
      const i = (y * w + x) * 4;
      if (Math.abs(data[i] - rgb[0]) <= tol && Math.abs(data[i + 1] - rgb[1]) <= tol && Math.abs(data[i + 2] - rgb[2]) <= tol) {
        count++;
        sx += x;
        sy += y;
        if (x < minx) minx = x;
        if (y < miny) miny = y;
        if (x > maxx) maxx = x;
        if (y > maxy) maxy = y;
      }
    }
  }
  return count ? { count, cx: sx / count, cy: sy / count, bbox: [minx, miny, maxx, maxy] } : { count: 0 };
}

/**
 * Tolerant comparison of two same-size RGBA images. Pixel metrics (mean absolute RGB error; share of pixels whose
 * largest channel error exceeds 32) and structure metrics (foreground masks against the board gradient: IoU, and
 * recall/precision within 2 px; per-palette-colour pixel counts and centroid offsets).
 */
export function compare(a, b, excluded = null) {
  const { width: w, height: h } = a;
  if (b.width !== w || b.height !== h) throw new Error("size mismatch");
  let sum = 0, over32 = 0, n = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!insideRounded(x, y, w, h, 16)) continue;
      const i = (y * w + x) * 4;
      const dr = Math.abs(a.data[i] - b.data[i]), dg = Math.abs(a.data[i + 1] - b.data[i + 1]), db = Math.abs(a.data[i + 2] - b.data[i + 2]);
      sum += (dr + dg + db) / 3;
      if (Math.max(dr, dg, db) > 32) over32++;
      n++;
    }
  }
  const fa = foreground(a, 24), fb = foreground(b, 24);
  let inter = 0, uni = 0, ca = 0, cb = 0;
  for (let i = 0; i < w * h; i++) {
    if (fa[i] && fb[i]) inter++;
    if (fa[i] || fb[i]) uni++;
    ca += fa[i];
    cb += fb[i];
  }
  const da = dilate(fa, w, h, 2), db2 = dilate(fb, w, h, 2);
  let bInA = 0, aInB = 0;
  for (let i = 0; i < w * h; i++) {
    if (fb[i] && da[i]) bInA++;
    if (fa[i] && db2[i]) aInB++;
  }
  const colors = {};
  for (const [name, rgb] of Object.entries(PALETTE)) {
    const sa = colorStats(a, rgb, 28), sb = colorStats(b, rgb, 28);
    if (sa.count < 40 && sb.count < 40) continue;
    colors[name] = {
      reference: sa.count, ours: sb.count,
      countRatio: sa.count ? +(sb.count / sa.count).toFixed(3) : null,
      centroidShift: sa.count && sb.count ? +Math.hypot(sb.cx - sa.cx, sb.cy - sa.cy).toFixed(2) : null,
      dx: sa.count && sb.count ? +(sb.cx - sa.cx).toFixed(2) : null,
      dy: sa.count && sb.count ? +(sb.cy - sa.cy).toFixed(2) : null,
    };
  }
  return {
    tiles: tileShifts(a, b, excluded),
    meanAbsError: +(sum / n).toFixed(3),
    over32Share: +(over32 / n).toFixed(5),
    foreground: {
      reference: ca, ours: cb, iou: uni ? +(inter / uni).toFixed(4) : 1,
      recallWithin2px: ca ? +(aInB / ca).toFixed(4) : 1,
      precisionWithin2px: cb ? +(bInA / cb).toFixed(4) : 1,
    },
    colors,
  };
}

function luminance(img) {
  const { width: w, height: h, data } = img;
  const lum = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) lum[i] = 0.2126 * data[i * 4] + 0.7152 * data[i * 4 + 1] + 0.0722 * data[i * 4 + 2];
  return lum;
}

/** Luminance gradient magnitude (|dI/dx| + |dI/dy|, forward differences). */
function edges(lum, w, h) {
  const e = new Float32Array(w * h);
  for (let y = 0; y < h - 1; y++) {
    for (let x = 0; x < w - 1; x++) {
      const i = y * w + x;
      e[i] = Math.abs(lum[i + 1] - lum[i]) + Math.abs(lum[i + w] - lum[i]);
    }
  }
  return e;
}

/** True when the tile touches the stroke band (±4 px) of rectangle `r`'s outline. */
function onOutline(tx, ty, tile, r) {
  if (!r) return false;
  const band = 4;
  const x0 = r.x - band, x1 = r.x + r.w + band, y0 = r.y - band, y1 = r.y + r.h + band;
  const overlapsOuter = tx < x1 && tx + tile > x0 && ty < y1 && ty + tile > y0;
  const insideInner = tx >= r.x + band && tx + tile <= r.x + r.w - band && ty >= r.y + band && ty + tile <= r.y + r.h - band;
  return overlapsOuter && !insideInner;
}

/**
 * Local geometry check on edges. Both images are reduced to luminance-gradient maps; the reference map is cut into
 * 32×32 tiles, and every tile with structure (at least 24 edge pixels of strength 24 or more; flat fills and smooth
 * gradients carry no position information and are skipped) is matched against ours shifted by up to ±6 px (least
 * sum of absolute edge differences; ties prefer the smaller shift). A tile whose structure is one straight edge
 * (structure tensor: smaller eigenvalue under a tenth of the larger) only fixes the shift across that edge, so its
 * shift is measured along the edge normal. Tiles on `excluded` (the dashed focus ring, whose dash phase is a known
 * gap) are reported separately. The same geometry gives shifts of 0–1 px; a misplaced item shows up as a larger
 * shift in its tiles.
 */
export function tileShifts(a, b, excluded = null, tile = 32, maxShift = 6, minEdges = 24) {
  const { width: w, height: h } = a;
  const la = luminance(a), lb = luminance(b);
  const ea = edges(la, w, h), eb = edges(lb, w, h);
  const shifts = [];
  for (let ty = 0; ty + tile <= h; ty += tile) {
    for (let tx = 0; tx + tile <= w; tx += tile) {
      let strong = 0, sxx = 0, syy = 0, sxy = 0;
      for (let y = Math.max(1, ty); y < Math.min(h - 1, ty + tile); y++) {
        for (let x = Math.max(1, tx); x < Math.min(w - 1, tx + tile); x++) {
          const i = y * w + x;
          if (ea[i] >= 24 && insideRounded(x, y, w, h, 16)) strong++;
          const gx = (la[i + 1] - la[i - 1]) / 2, gy = (la[i + w] - la[i - w]) / 2;
          sxx += gx * gx; syy += gy * gy; sxy += gx * gy;
        }
      }
      if (strong < minEdges) continue;
      let best = { dx: 0, dy: 0, sad: Infinity };
      for (let dy = -maxShift; dy <= maxShift; dy++) {
        for (let dx = -maxShift; dx <= maxShift; dx++) {
          if (tx + dx < 0 || ty + dy < 0 || tx + dx + tile > w || ty + dy + tile > h) continue;
          let sad = 0;
          for (let y = ty; y < ty + tile; y++) {
            let i = y * w + tx;
            let j = (y + dy) * w + tx + dx;
            for (let x = 0; x < tile; x++, i++, j++) sad += Math.abs(ea[i] - eb[j]);
          }
          const size = Math.hypot(dx, dy);
          const bestSize = Math.hypot(best.dx, best.dy);
          if (sad < best.sad - 1e-6 || (Math.abs(sad - best.sad) <= 1e-6 && size < bestSize)) best = { dx, dy, sad };
        }
      }
      const half = (sxx + syy) / 2, root = Math.sqrt(((sxx - syy) / 2) ** 2 + sxy * sxy);
      const l1 = half + root, l2 = half - root;
      let shift;
      let kind;
      if (l1 > 0 && l2 < 0.1 * l1) {
        // One straight edge: only the component across it is measured.
        const nx = sxy !== 0 ? l1 - syy : sxx >= syy ? 1 : 0, ny = sxy !== 0 ? sxy : sxx >= syy ? 0 : 1;
        const len = Math.hypot(nx, ny) || 1;
        shift = Math.abs((best.dx * nx + best.dy * ny) / len);
        kind = "edge";
      } else {
        shift = Math.max(Math.abs(best.dx), Math.abs(best.dy));
        kind = "corner";
      }
      shifts.push({ x: tx, y: ty, dx: best.dx, dy: best.dy, shift: +shift.toFixed(2), kind, ring: onOutline(tx, ty, tile, excluded) });
    }
  }
  const judged = shifts.filter((s) => !s.ring);
  const ring = shifts.filter((s) => s.ring);
  const share = (list, k) => (list.length ? +(list.filter((s) => s.shift <= k).length / list.length).toFixed(4) : 1);
  return {
    tiles: judged.length,
    within1px: share(judged, 1),
    within2px: share(judged, 2),
    maxShift: judged.length ? Math.max(...judged.map((s) => s.shift)) : 0,
    outliers: judged.filter((s) => s.shift > 2),
    focusRingTiles: ring.length,
    focusRingWithin2px: share(ring, 2),
  };
}

/** |a − b| amplified ×4, as a viewable heat image. */
export function diffImage(a, b) {
  const out = new ImageData(a.width, a.height);
  for (let i = 0; i < a.data.length; i += 4) {
    const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
    const v = Math.min(255, d * 4);
    out.data[i] = v;
    out.data[i + 1] = Math.min(255, v * 0.6);
    out.data[i + 2] = Math.min(255, v * 0.2);
    out.data[i + 3] = 255;
  }
  return out;
}

export function toPNGDataURL(img) {
  const c = canvasFor(img.width, img.height);
  c.getContext("2d").putImageData(img, 0, 0);
  return c.toDataURL("image/png");
}

/** Box-filter downscale by an integer factor (used for snapshot thumbnails). */
export function downscale(img, f) {
  const w = Math.floor(img.width / f), h = Math.floor(img.height / f);
  const out = new ImageData(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const acc = [0, 0, 0, 0];
      for (let dy = 0; dy < f; dy++) for (let dx = 0; dx < f; dx++) {
        const i = ((y * f + dy) * img.width + (x * f + dx)) * 4;
        for (let k = 0; k < 4; k++) acc[k] += img.data[i + k];
      }
      const o = (y * w + x) * 4;
      for (let k = 0; k < 4; k++) out.data[o + k] = Math.round(acc[k] / (f * f));
    }
  }
  return out;
}

/** Share of pixels whose largest channel differs by more than `tol` (snapshot tolerance check). */
export function changedShare(a, b, tol) {
  if (a.width !== b.width || a.height !== b.height) return 1;
  let changed = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
    if (d > tol) changed++;
  }
  return changed / (a.width * a.height);
}
