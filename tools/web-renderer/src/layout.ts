// SPDX-License-Identifier: Apache-2.0
// Port of `MGViewport` and `MGLayout` (Sources/MartyGraphics/MGLayout.swift): one uniform world→screen scale with y
// flipped, item footprints, the vector shaft start, and the greedy collision-free label placement.

import { type MGCamera, type MGItem, type MGKind, type MGPoint, P, add, n, polar, sub } from "./model.js";
import { characterCount } from "./unicode.js";

// MARK: rectangles (CGRect semantics; a null rect is `null`)

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export const rect = (x: number, y: number, w: number, h: number): Rect => ({ x, y, w, h });
export const minX = (r: Rect) => r.x;
export const minY = (r: Rect) => r.y;
export const maxX = (r: Rect) => r.x + r.w;
export const maxY = (r: Rect) => r.y + r.h;
export const midX = (r: Rect) => r.x + r.w / 2;
export const midY = (r: Rect) => r.y + r.h / 2;

/** `CGRect.insetBy`: negative values grow. A rect inset past zero size becomes null. */
export function inset(r: Rect | null, dx: number, dy: number): Rect | null {
  if (!r) return null;
  const out = rect(r.x + dx, r.y + dy, r.w - 2 * dx, r.h - 2 * dy);
  if (out.w < 0 || out.h < 0) return null;
  return out;
}

export function union(a: Rect, b: Rect): Rect {
  const x0 = Math.min(a.x, b.x);
  const y0 = Math.min(a.y, b.y);
  const x1 = Math.max(maxX(a), maxX(b));
  const y1 = Math.max(maxY(a), maxY(b));
  return rect(x0, y0, x1 - x0, y1 - y0);
}

/** Overlap with positive area, or null. Rectangles that only touch do not intersect. */
export function intersection(a: Rect, b: Rect): Rect | null {
  const x0 = Math.max(a.x, b.x);
  const y0 = Math.max(a.y, b.y);
  const x1 = Math.min(maxX(a), maxX(b));
  const y1 = Math.min(maxY(a), maxY(b));
  if (x1 <= x0 || y1 <= y0) return null;
  return rect(x0, y0, x1 - x0, y1 - y0);
}

export function contains(outer: Rect, inner: Rect): boolean {
  return inner.x >= outer.x && inner.y >= outer.y && maxX(inner) <= maxX(outer) && maxY(inner) <= maxY(outer);
}

export function containsPoint(r: Rect, x: number, y: number): boolean {
  return x >= r.x && x <= maxX(r) && y >= r.y && y <= maxY(r);
}

// MARK: viewport

export interface Size {
  width: number;
  height: number;
}

export class Viewport {
  constructor(readonly size: Size, readonly scale: number, readonly center: MGPoint) {}

  /** `MGViewport(size:width:height:camera:padding:)`. */
  static fit(size: Size, width: number, height: number, camera?: MGCamera, padding = 18): Viewport {
    const fit = Math.min((size.width - 2 * padding) / width, (size.height - 2 * padding) / height);
    const scale = Math.max(1, fit) * (camera?.zoom ?? 1);
    return new Viewport(size, scale, P(camera?.x ?? width / 2, camera?.y ?? height / 2));
  }

  point(p: MGPoint): { x: number; y: number } {
    return { x: this.size.width / 2 + (p.x - this.center.x) * this.scale, y: this.size.height / 2 - (p.y - this.center.y) * this.scale };
  }

  length(d: number): number {
    return d * this.scale;
  }
}

// MARK: layout

/** Screen-space footprint of an item (for focus rings, highlights and label obstacles). */
export function bounds(start: MGItem, items: MGItem[], vp: Viewport): Rect | null {
  let item = start;
  const visited = new Set<string>();
  while (item.kind === "highlight") {
    if (visited.has(item.id)) return null;
    visited.add(item.id);
    const target = items.find((i) => i.id === item.ref);
    if (!target) return null;
    item = target;
  }
  const around = (p: MGPoint, r: number): Rect => {
    const c = vp.point(p);
    const s = vp.length(r);
    return rect(c.x - s, c.y - s, 2 * s, 2 * s);
  };
  const box = (pts: MGPoint[]): Rect | null => {
    if (!pts.length) return null;
    const f = vp.point(pts[0]);
    let r = rect(f.x, f.y, 0, 0);
    for (const q of pts.slice(1)) {
      const s = vp.point(q);
      r = union(r, rect(s.x, s.y, 0, 0));
    }
    return r;
  };
  const first = item.pts[0];
  switch (item.kind as MGKind) {
    case "body": return first ? around(first, n(item, "size", 1) / (item.flags.has("ball") ? 2 : 1.6)) : null;
    case "node": return first ? around(first, n(item, "r", 0.5)) : null;
    case "pulley": case "orbit": return first ? around(first, n(item, "r")) : null;
    case "incline": {
      if (!first) return null;
      const b = n(item, "base");
      const h = b * Math.tan((n(item, "angle") * Math.PI) / 180);
      return box([first, add(first, P(b, 0)), add(first, P(b, h))]);
    }
    case "vector":
      if (!first) return null;
      return inset(box([first, add(first, polar(n(item, "angle"), n(item, "len")))]), -6, -6);
    case "axes": case "plot": case "bars":
      if (!first) return null;
      return box([first, add(first, P(n(item, "w"), n(item, "h")))]);
    case "array": {
      if (!first) return null;
      const w = n(item, "cell", 1) * item.list.length;
      return inset(box([sub(first, P(w / 2, n(item, "cell", 1) / 2)), add(first, P(w / 2, n(item, "cell", 1) / 2))]), 0, -vp.length(0.5));
    }
    case "table": {
      if (!first) return null;
      const w = n(item, "cw", 1.6) * n(item, "cols", 1);
      const h = n(item, "rh", 0.7) * n(item, "rows", 1);
      return box([sub(first, P(w / 2, h / 2)), add(first, P(w / 2, h / 2))]);
    }
    case "text": {
      if (!first) return null;
      if (item.flags.has("code")) {
        const c = vp.point(first);
        const t = item.text ?? "";
        const s = { width: characterCount(t) * 14 * 0.6 + 4, height: 14 * 1.35 + 4 };
        return rect(c.x, c.y - s.height / 2, s.width, s.height);
      }
      const s = textSize(item.text ?? "", item.flags.has("title") ? 20 : 14);
      const c = vp.point(first);
      return rect(c.x - s.width / 2, c.y - s.height / 2, s.width, s.height);
    }
    case "highlight": return null;
    case "edge": {
      const a = items.find((i) => i.id === item.ref)?.pts[0];
      const b = items.find((i) => i.id === item.ref2)?.pts[0];
      if (!a || !b) return null;
      return box([a, b]);
    }
    case "line": case "spring": case "rope": case "path": case "region":
      return box(item.pts);
  }
}

/** Rough text box for label placement (`MGLayout.textSize`). */
export function textSize(s: string, font: number): Size {
  return { width: characterCount(s) * font * 0.56 + 14, height: font * 1.35 + 6 };
}

/** Where a vector should start so its shaft leaves the body's edge instead of being buried in it. */
export function shaftStart(center: { x: number; y: number }, angle: number, body: MGItem | undefined, vp: Viewport): { x: number; y: number } {
  if (!body || (body.kind !== "body" && body.kind !== "node")) return center;
  const dx = Math.cos((angle * Math.PI) / 180);
  const dy = -Math.sin((angle * Math.PI) / 180);
  let distance: number;
  if (body.kind === "node" || body.flags.has("ball")) {
    distance = vp.length(body.kind === "node" ? n(body, "r", 0.5) : n(body, "size", 1) / 2);
  } else {
    const half = vp.length(n(body, "size", 1) / 2);
    const rel = ((angle - n(body, "angle")) * Math.PI) / 180;
    distance = half / Math.max(Math.abs(Math.cos(rel)), Math.abs(Math.sin(rel)));
  }
  return { x: center.x + dx * distance, y: center.y + dy * distance };
}

export interface LabelRequest {
  id: string;
  anchor: { x: number; y: number };
  /** Preferred push-out direction (screen space). */
  direction: { dx: number; dy: number };
  size: Size;
}

const TURNS = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6];

/** Greedy collision-free label placement (`MGLayout.place`). Deterministic. */
export function place(requests: LabelRequest[], obstacles: Rect[], area: Rect): Map<string, Rect> {
  const placed: Rect[] = [];
  const out = new Map<string, Rect>();
  for (const r of requests) {
    const len = Math.max(0.001, Math.hypot(r.direction.dx, r.direction.dy));
    const base = Math.atan2(r.direction.dy / len, r.direction.dx / len);
    let best: { rect: Rect; cost: number } | null = null;
    search: for (let ring = 0; ring < 3; ring++) {
      for (let k = 0; k < TURNS.length; k++) {
        const a = base + (TURNS[k] * Math.PI) / 6;
        const gap = 8 + ring * (r.size.height + 6);
        const cx = r.anchor.x + Math.cos(a) * (r.size.width / 2 + gap);
        const cy = r.anchor.y + Math.sin(a) * (r.size.height / 2 + gap);
        const candidate = rect(cx - r.size.width / 2, cy - r.size.height / 2, r.size.width, r.size.height);
        const preference = ring * 30 + k * 2;
        let cost = preference;
        for (const p of placed) {
          const i = intersection(p, candidate);
          if (i) cost += i.w * i.h + 400;
        }
        for (const o of obstacles) {
          const i = intersection(o, candidate);
          if (i) cost += i.w * i.h * 0.6 + 150;
        }
        if (!contains(area, candidate)) {
          const i = intersection(area, candidate);
          cost += candidate.w * candidate.h - (i ? i.w * i.h : 0) + 300;
        }
        if (best === null || cost < best.cost) best = { rect: candidate, cost };
        if (cost <= preference) break search;
      }
    }
    if (best) {
      placed.push(best.rect);
      out.set(r.id, best.rect);
    }
  }
  return out;
}
