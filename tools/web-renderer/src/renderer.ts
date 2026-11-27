// SPDX-License-Identifier: Apache-2.0
// Port of `MGCanvasRenderer.draw` (Sources/MartyGraphics/MGCanvasRenderer.swift) to the HTML canvas: neon-on-dark
// board, glowing vectors drawn from the body's edge, collision-free labels, pulsing focus. No state; the caller owns
// time and steps. Geometry, colours, line widths, dash patterns and draw order follow the Swift source line by line.

import { format } from "./format.js";
import {
  type Anchor, type Pt, type TextStyle, drawText, drawTextIn, ellipse, fill, layer, layoutText, linearGradient,
  polyline, radialGradient, rectPath, roundedRect, setPixelGrid, stroke, trimPolyline,
} from "./gfx.js";
import {
  type LabelRequest, type Rect, Viewport, bounds, inset, maxX, maxY, midX, midY, minX, minY, place, rect, shaftStart,
} from "./layout.js";
import { MGLimits } from "./limits.js";
import { type MGItem, type MGKind, type MGPoint, type MGScene, P, add, isEmptyTable, lerp, n, polar, sub } from "./model.js";
import { type RGBA, type Theme, board, color as roleColor, css, opacity } from "./theme.js";
import { spring } from "./timeline.js";

export interface RenderInput {
  scene: MGScene;
  items: MGItem[];
  viewport: Viewport;
  theme?: Theme;
  /** Draw-on progress per item id, 0...1. Missing means fully drawn. */
  appear?: Record<string, number>;
  focus?: string;
  /** Items to point at with glow rings. */
  emphasis?: Set<string>;
  /** Numbered markers (item id → n). */
  markers?: Record<string, number>;
  time: number;
  tableRows?: Record<string, Set<number>>;
  tableCells?: Record<string, Set<number>>;
}

const LAYER: Record<MGKind, number> = {
  axes: 0, plot: 0, bars: 0, incline: 1, line: 1, orbit: 1, path: 2, rope: 2, spring: 3, pulley: 3, edge: 3, body: 4,
  node: 4, array: 4, vector: 5, highlight: 6, text: 7, table: 4, region: 0,
};

const ease = (p: number) => {
  const x = Math.min(1, Math.max(0, p));
  return 1 - Math.pow(1 - x, 3);
};

const SMALL: TextStyle = { size: 12, weight: "medium" };
const LABEL: TextStyle = { size: 13, weight: "semibold" };

/** Swift `Int(x.rounded())` on the fan key: schoolbook rounding, half away from zero. */
const roundHalfAway = (x: number) => (x < 0 ? -Math.round(-x) : Math.round(x));

/** Draws one 2D frame into `ctx` (logical points; `dpr` device pixels per point, already applied as the transform). */
export function draw(input: RenderInput, ctx: CanvasRenderingContext2D, dpr = 1): void {
  const vp = input.viewport;
  const theme = input.theme ?? board;
  const size = vp.size;
  const appear = input.appear ?? {};
  const emphasis = input.emphasis ?? new Set<string>();
  const markers = input.markers ?? {};
  setPixelGrid(dpr);

  // Board.
  const full = rect(0, 0, size.width, size.height);
  fill(ctx, rectPath(full), linearGradient(ctx, [theme.backgroundTop, theme.backgroundBottom], { x: 0, y: 0 }, { x: 0, y: size.height }));
  if (!input.scene.is3D) grid(ctx, vp, input.scene, theme);

  const byID = new Map<string, MGItem>();
  for (const i of input.items) if (!byID.has(i.id)) byID.set(i.id, i);
  const labels: LabelRequest[] = [];
  const labelStyle = new Map<string, { text: string; color: RGBA; alpha: number }>();
  const obstacles: Array<Rect | null> = [];

  // Parallel arrows on one body fan out sideways so they never hide each other.
  const fan = new Map<string, number>();
  const groups = new Map<string, MGItem[]>();
  for (const v of input.items) {
    if (v.kind !== "vector" || v.ref === undefined) continue;
    const key = `${v.ref}|${roundHalfAway((((n(v, "angle") % 360) + 360) % 360))}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(v);
  }
  for (const g of groups.values()) {
    if (g.length > 1) g.forEach((v, k) => fan.set(v.id, (k - (g.length - 1) / 2) * 11));
  }

  const sorted = input.items.map((item, index) => ({ item, index }))
    .sort((a, b) => (LAYER[a.item.kind] ?? 0) - (LAYER[b.item.kind] ?? 0) || a.index - b.index)
    .map((e) => e.item);

  for (const item of sorted) {
    const p = ease(appear[item.id] ?? 1);
    const color = roleColor(theme, item.color);
    const labelColor = emphasis.has(item.id) ? roleColor(theme, "yellow") : color;
    const label = (text: string | undefined, anchor: Pt, dir: { dx: number; dy: number }, alpha = 1) => {
      if (!text || !(alpha > 0.01)) return;
      const s = layoutText(ctx, text, LABEL, 400);
      const id = `${item.id}#${labels.length}`;
      labels.push({ id, anchor, direction: dir, size: { width: s.width + 14, height: s.height + 8 } });
      labelStyle.set(id, { text, color: labelColor, alpha });
    };

    switch (item.kind) {
      case "body": {
        const at = item.pts[0];
        if (!at) continue;
        const c = vp.point(at);
        const pop = spring(p * 0.9);
        const side = vp.length(n(item, "size", 1)) * Math.max(0.01, pop);
        const ball = item.flags.has("ball");
        ctx.save();
        ctx.translate(c.x, c.y);
        ctx.rotate((-n(item, "angle") * Math.PI) / 180);
        const r = rect(-side / 2, -side / 2, side, side);
        const shape = ball ? ellipse(r) : roundedRect(r, side * 0.14);
        layer(ctx, dpr, (l) => {
          fill(l, shape, ball
            ? radialGradient(l, [opacity(color, 0.95), opacity(color, 0.55)], { x: -side * 0.18, y: -side * 0.2 }, 1, side * 0.7)
            : linearGradient(l, [opacity(color, 0.95), opacity(color, 0.6)], { x: 0, y: -side / 2 }, { x: 0, y: side / 2 }));
        }, { shadow: { color: opacity(color, 0.55), radius: 10 } });
        stroke(ctx, shape, css({ r: 255, g: 255, b: 255, a: 0.35 }), { width: 1.5 });
        ctx.restore();
        const box = rect(c.x - side / 2, c.y - side / 2, side, side);
        obstacles.push(box);
        if (item.label) {
          const style: TextStyle = { size: 13, weight: "bold" };
          const m = layoutText(ctx, item.label, style, 300);
          if (m.width < side * (ball ? 0.72 : 0.9) && m.height < side * 0.7) drawText(ctx, item.label, style, { r: 255, g: 255, b: 255, a: 1 }, c);
          else label(item.label, { x: c.x, y: maxY(box) }, { dx: 0, dy: 1 });
        }
        break;
      }
      case "incline": {
        const o = item.pts[0];
        if (!o) continue;
        const b = n(item, "base");
        const h = b * Math.tan((n(item, "angle") * Math.PI) / 180);
        const tri = polyline([vp.point(o), vp.point(add(o, P(b, 0))), vp.point(add(o, P(b, h)))], true);
        fill(ctx, tri, linearGradient(ctx, [opacity(color, 0.32), opacity(color, 0.12)], vp.point(add(o, P(b, h))), vp.point(o)));
        stroke(ctx, tri, css(opacity(color, 0.85)), { width: 2 });
        if (n(item, "angle") > 1) {
          const c = vp.point(o);
          const arc = new Path2D();
          arc.arc(c.x, c.y, vp.length(Math.min(1.2, b * 0.25)), 0, (-n(item, "angle") * Math.PI) / 180, true);
          stroke(ctx, arc, css(opacity(roleColor(theme, "yellow"), 0.8)), { width: 1.5 });
        }
        label(item.label, vp.point(add(o, P(b * 0.55, h * 0.55))), { dx: -0.6, dy: -1 });
        obstacles.push(bounds(item, input.items, vp));
        break;
      }
      case "line": {
        if (item.pts.length !== 2) continue;
        const a = vp.point(item.pts[0]);
        const b = vp.point(item.pts[1]);
        const path2 = polyline(trimPolyline([a, b], p));
        if (item.flags.has("ground")) {
          stroke(ctx, path2, css(opacity(color, 0.9)), { width: 3 });
          const len = Math.hypot(b.x - a.x, b.y - a.y);
          const count = Math.trunc(len / 14);
          if (count > 0 && p >= 1) {
            const hatch = new Path2D();
            const ux = (b.x - a.x) / len;
            const uy = (b.y - a.y) / len;
            const nx = uy;
            const ny = -ux; // screen normal: below a left-to-right line
            for (let k = 0; k <= count; k++) {
              const s = k * 14;
              const q = { x: a.x + ux * s, y: a.y + uy * s };
              hatch.moveTo(q.x, q.y);
              hatch.lineTo(q.x - nx * 8 - ux * 6, q.y - ny * 8 - uy * 6);
            }
            stroke(ctx, hatch, css(opacity(color, 0.35)), { width: 1 });
          }
        } else {
          stroke(ctx, path2, css(opacity(color, 0.85)), { width: 2, cap: "round", dash: item.flags.has("dashed") ? [6, 5] : [] });
        }
        break;
      }
      case "vector": {
        const from = item.pts[0];
        if (!from || !(n(item, "len") > 0)) continue;
        const angle = n(item, "angle");
        const body = item.ref !== undefined ? byID.get(item.ref) : undefined;
        const center = vp.point(from);
        let start = shaftStart(center, angle, body, vp);
        const len = vp.length(n(item, "len")) * p;
        const dx = Math.cos((angle * Math.PI) / 180);
        const dy = -Math.sin((angle * Math.PI) / 180);
        const shift = fan.get(item.id);
        if (shift !== undefined) start = { x: start.x - dy * shift, y: start.y + dx * shift };
        const tip = { x: start.x + dx * len, y: start.y + dy * len };
        arrow(ctx, dpr, start, tip, color, item.flags.has("dashed"), item.flags.has("dashed") ? 2 : 3.2);
        label(item.label, tip, { dx, dy }, p > 0.6 ? (p - 0.6) / 0.4 : 0);
        break;
      }
      case "axes": {
        const o = item.pts[0];
        if (!o) continue;
        const origin = vp.point(o);
        const xEnd = vp.point(add(o, P(n(item, "w"), 0)));
        const yEnd = vp.point(add(o, P(0, n(item, "h"))));
        arrow(ctx, dpr, origin, xEnd, color, false, 1.5, false);
        arrow(ctx, dpr, origin, yEnd, color, false, 1.5, false);
        if (item.list.length === 2) {
          small(ctx, item.list[0], { x: xEnd.x - 4, y: xEnd.y + 14 }, theme.subtleInk, "trailing");
          small(ctx, item.list[1], { x: yEnd.x + 10, y: yEnd.y + 4 }, theme.subtleInk, "leading");
        }
        break;
      }
      case "plot":
        plot(ctx, dpr, item, vp, theme, color, p);
        label(item.label, vp.point(add(item.pts[0], P(n(item, "w") / 2, n(item, "h")))), { dx: 0, dy: -1 });
        obstacles.push(bounds(item, input.items, vp));
        break;
      case "spring": {
        if (item.pts.length !== 2) continue;
        coil(ctx, dpr, vp.point(item.pts[0]), vp.point(item.pts[1]), Math.trunc(n(item, "coils", 8)), vp.length(0.28), color);
        obstacles.push(inset(bounds(item, input.items, vp), 0, -vp.length(0.3)));
        const mid = vp.point(lerp(item.pts[0], item.pts[1], 0.5));
        label(item.label, { x: mid.x, y: mid.y - vp.length(0.3) }, { dx: 0, dy: -1 });
        break;
      }
      case "pulley": {
        const at = item.pts[0];
        if (!at) continue;
        const c = vp.point(at);
        const r = vp.length(n(item, "r"));
        const disc = ellipse(rect(c.x - r, c.y - r, 2 * r, 2 * r));
        fill(ctx, disc, radialGradient(ctx, [opacity(color, 0.5), opacity(color, 0.15)], c, 0, r));
        stroke(ctx, disc, css(color), { width: 2.5 });
        fill(ctx, ellipse(rect(c.x - 4, c.y - 4, 8, 8)), css(theme.ink));
        break;
      }
      case "rope":
        stroke(ctx, polyline(item.pts.map((q) => vp.point(q))), css(opacity(theme.ink, 0.75)), { width: 2 });
        break;
      case "orbit": {
        const at = item.pts[0];
        if (!at) continue;
        const c = vp.point(at);
        const r = vp.length(n(item, "r"));
        stroke(ctx, ellipse(rect(c.x - r, c.y - r, 2 * r, 2 * r), p), css(opacity(color, 0.7)), { width: 2, dash: [7, 6] });
        label(item.label, { x: c.x, y: c.y - r }, { dx: 0.4, dy: -1 });
        break;
      }
      case "path": {
        if (item.pts.length <= 1) continue;
        const pts = trimPolyline(item.pts.map((q) => vp.point(q)), p);
        layer(ctx, dpr, (l) => {
          stroke(l, polyline(pts), css(opacity(color, 0.9)), { width: 2.5, cap: "round", join: "round", dash: item.flags.has("dashed") ? [6, 6] : [] });
        }, { shadow: { color: opacity(color, 0.6), radius: 5 } });
        break;
      }
      case "text": {
        const atW = item.pts[0];
        const s = item.text;
        if (!atW || s === undefined) continue;
        const at = vp.point(atW);
        ctx.save();
        ctx.globalAlpha = p;
        if (item.flags.has("callout")) {
          const style: TextStyle = { size: 15, weight: "semibold" };
          const m = layoutText(ctx, s, style, vp.size.width * 0.8);
          const box = rect(at.x - m.width / 2 - 12, at.y - m.height / 2 - 7, m.width + 24, m.height + 14);
          fill(ctx, roundedRect(box, 12), css(theme.labelFill));
          stroke(ctx, roundedRect(box, 12), css(opacity(color, 0.9)), { width: 1.5 });
          fill(ctx, rectPath(rect(box.x + 6, box.y + 7, 3, box.h - 14)), css(color));
          drawTextIn(ctx, s, style, theme.ink, rect(at.x - m.width / 2 + 2, at.y - m.height / 2, m.width + 2, m.height));
          obstacles.push(box);
        } else if (item.flags.has("code")) {
          // Monospaced and left-aligned at `at`, so indented lines stack into a readable listing.
          const style: TextStyle = { size: 14, weight: "medium", design: "monospaced" };
          const m = drawText(ctx, s, style, color, at, "leading");
          obstacles.push(rect(at.x, at.y - m.height / 2, m.width, m.height));
        } else {
          const style: TextStyle = { size: item.flags.has("title") ? 20 : 14, weight: item.flags.has("title") ? "bold" : "medium" };
          const m = drawText(ctx, s, style, color, at);
          obstacles.push(rect(at.x - m.width / 2, at.y - m.height / 2, m.width, m.height));
        }
        ctx.restore();
        break;
      }
      case "highlight": {
        const target = item.ref !== undefined ? byID.get(item.ref) : undefined;
        const r = target ? bounds(target, input.items, vp) : null;
        if (!target || !r) continue;
        const pulse = 0.55 + 0.45 * Math.sin(input.time * 4);
        const box = inset(r, -10, -10)!;
        const shape = target.kind === "node" || target.flags.has("ball") ? ellipse(box) : roundedRect(box, 12);
        layer(ctx, dpr, (l) => {
          if (target.kind !== "node") fill(l, shape, css(opacity(color, 0.1)));
          stroke(l, shape, css(opacity(color, pulse)), { width: 2.5 });
        }, { shadow: { color: opacity(color, 0.9), radius: 12 }, opacity: p });
        label(item.label, { x: midX(box), y: minY(box) }, { dx: 0, dy: -1 });
        break;
      }
      case "bars":
        bars(ctx, dpr, item, vp, theme, p);
        obstacles.push(bounds(item, input.items, vp));
        break;
      case "array": {
        array(ctx, dpr, item, vp, theme, color, p);
        obstacles.push(bounds(item, input.items, vp));
        const c = item.pts[0];
        if (item.label && c) label(item.label, vp.point(add(c, P(0, n(item, "cell", 1) / 2))), { dx: 0, dy: -1 });
        break;
      }
      case "region": {
        if (item.pts.length < 3) continue;
        const shape = polyline(item.pts.map((q) => vp.point(q)), true);
        ctx.save();
        ctx.globalAlpha = p;
        fill(ctx, shape, css(opacity(color, 0.2)));
        stroke(ctx, shape, css(opacity(color, 0.85)), { width: 1.8, dash: item.flags.has("dashed") ? [6, 5] : [] });
        ctx.restore();
        const r = bounds(item, input.items, vp);
        if (r) label(item.label, { x: midX(r), y: minY(r) }, { dx: 0, dy: -1 });
        break;
      }
      case "table": {
        // A table with no data row is not drawn: no header-only grid before its first fill.
        if (isEmptyTable(item)) continue;
        table(ctx, dpr, item, vp, theme, color, p, input.tableRows?.[item.id] ?? new Set(), input.tableCells?.[item.id] ?? new Set());
        const r = bounds(item, input.items, vp);
        if (r) {
          obstacles.push(r);
          if (item.label) {
            // The caption fades in with the grid instead of appearing before any row.
            ctx.save();
            ctx.globalAlpha = p;
            drawText(ctx, item.label, { size: 13, weight: "bold" }, theme.ink, { x: minX(r) + 2, y: minY(r) - 12 }, "leading");
            ctx.restore();
          }
        }
        break;
      }
      case "node": {
        const at = item.pts[0];
        if (!at) continue;
        const c = vp.point(at);
        const r = vp.length(n(item, "r", 0.5)) * spring(p * 0.9);
        const disc = ellipse(rect(c.x - r, c.y - r, 2 * r, 2 * r));
        layer(ctx, dpr, (l) => {
          fill(l, disc, radialGradient(l, [opacity(color, 0.55), opacity(color, 0.22)], c, 0, r));
        }, { shadow: { color: opacity(color, 0.5), radius: 8 } });
        stroke(ctx, disc, css(color), { width: 2 });
        if (item.text !== undefined) drawText(ctx, item.text, { size: Math.max(10, Math.min(18, r * 0.8)), weight: "bold", design: "rounded" }, theme.ink, c);
        obstacles.push(rect(c.x - r, c.y - r, 2 * r, 2 * r));
        break;
      }
      case "edge": {
        const a = item.ref !== undefined ? byID.get(item.ref) : undefined;
        const b = item.ref2 !== undefined ? byID.get(item.ref2) : undefined;
        if (!a || !b || !a.pts[0] || !b.pts[0]) continue;
        const pa = vp.point(a.pts[0]);
        const pb = vp.point(b.pts[0]);
        const d = Math.hypot(pb.x - pa.x, pb.y - pa.y);
        if (!(d > 1)) continue;
        const ux = (pb.x - pa.x) / d;
        const uy = (pb.y - pa.y) / d;
        const ra = vp.length(n(a, "r", 0.5));
        const rb = vp.length(n(b, "r", 0.5)) + (item.flags.has("dir") ? 2 : 0);
        const s = { x: pa.x + ux * ra, y: pa.y + uy * ra };
        const e = { x: s.x + (pb.x - ux * rb - s.x) * p, y: s.y + (pb.y - uy * rb - s.y) * p };
        if (item.flags.has("dir")) arrow(ctx, dpr, s, e, color, false, 2, false);
        else stroke(ctx, polyline([s, e]), css(color), { width: 2 });
        label(item.label, { x: (s.x + e.x) / 2, y: (s.y + e.y) / 2 }, { dx: -uy, dy: ux });
        break;
      }
    }
  }

  // Emphasis rings, then numbered markers (object list ↔ board), drawn under labels.
  for (const id of [...emphasis].sort()) {
    const target = byID.get(id);
    const r = target ? bounds(target, input.items, vp) : null;
    if (!r) continue;
    const box = inset(r, -9, -9)!;
    const glow = roleColor(theme, "yellow");
    layer(ctx, dpr, (l) => stroke(l, roundedRect(box, 10), css(opacity(glow, 0.9)), { width: 2.5 }), { shadow: { color: opacity(glow, 0.9), radius: 10 } });
  }
  for (const [id, num] of Object.entries(markers).sort((a, b) => a[1] - b[1])) {
    const target = byID.get(id);
    const r = target ? bounds(target, input.items, vp) : null;
    if (!target || !r) continue;
    const c = markerSpot(target, r, vp, target.ref !== undefined ? byID.get(target.ref) : undefined);
    obstacles.push(rect(c.x - 12, c.y - 12, 24, 24));
    const disc = ellipse(rect(c.x - 10, c.y - 10, 20, 20));
    const ring = emphasis.has(id) ? roleColor(theme, "yellow") : theme.subtleInk;
    fill(ctx, disc, css(theme.labelFill));
    stroke(ctx, disc, css(ring), { width: 1.5 });
    drawText(ctx, String(num), { size: 11, weight: "bold", design: "rounded" }, theme.ink, c);
  }
  // Focus ring (step focus), drawn under labels so text stays readable.
  if (input.focus !== undefined) {
    const target = byID.get(input.focus);
    const r = target && target.kind !== "highlight" ? bounds(target, input.items, vp) : null;
    if (r) {
      const pulse = 0.35 + 0.35 * (0.5 + 0.5 * Math.sin(input.time * 3.2));
      const box = inset(r, -8, -8)!;
      stroke(ctx, roundedRect(box, 10), css(opacity(theme.ink, pulse)), { width: 1.5, dash: [4, 4] });
    }
  }

  const placed = place(labels, obstacles.filter((o): o is Rect => o !== null), inset(full, 4, 4) ?? full);
  for (const r of labels) {
    const box = placed.get(r.id);
    const st = labelStyle.get(r.id);
    if (!box || !st) continue;
    ctx.save();
    ctx.globalAlpha = st.alpha;
    fill(ctx, roundedRect(box, 7), css(theme.labelFill));
    stroke(ctx, roundedRect(box, 7), css(opacity(st.color, 0.55)), { width: 1 });
    drawText(ctx, st.text, LABEL, theme.ink, { x: midX(box), y: midY(box) });
    ctx.restore();
  }
}

// MARK: pieces

/** Where an object's number sits, always touching its object. */
function markerSpot(item: MGItem, r: Rect, vp: Viewport, body?: MGItem): Pt {
  const o = item.pts[0];
  if (item.kind === "incline" && o) {
    const th = n(item, "angle");
    const b = n(item, "base");
    const len = b / Math.max(Math.cos((th * Math.PI) / 180), 1e-6);
    return vp.point(add(add(o, polar(th, len * 0.38)), polar(th + 90, 0.45)));
  }
  if (item.kind === "vector" && o) {
    const a = (n(item, "angle") * Math.PI) / 180;
    const dx = Math.cos(a);
    const dy = -Math.sin(a);
    const start = shaftStart(vp.point(o), n(item, "angle"), body, vp);
    const along = vp.length(n(item, "len")) * 0.6;
    return { x: start.x + dx * along + dy * 15, y: start.y + dy * along - dx * 15 };
  }
  return { x: minX(r) + 2, y: minY(r) + 2 };
}

function grid(ctx: CanvasRenderingContext2D, vp: Viewport, scene: MGScene, theme: Theme): void {
  const dots = new Path2D();
  const stepWorld = Math.max(1, roundHalfAway(scene.width / 24));
  for (let x = 0; x <= scene.width; x += stepWorld) {
    for (let y = 0; y <= scene.height; y += stepWorld) {
      const p = vp.point(P(x, y));
      dots.moveTo(p.x + 1, p.y);
      dots.ellipse(p.x, p.y, 1, 1, 0, 0, Math.PI * 2);
    }
  }
  fill(ctx, dots, css(theme.grid));
}

function arrow(ctx: CanvasRenderingContext2D, dpr: number, a: Pt, b: Pt, color: RGBA, dashed: boolean, width: number, glow = true): void {
  const d = Math.hypot(b.x - a.x, b.y - a.y);
  if (!(d > 0.5)) return;
  const ux = (b.x - a.x) / d;
  const uy = (b.y - a.y) / d;
  const head = Math.min(14, Math.max(7, d * 0.35)) * (width > 2.5 ? 1 : 0.8);
  const base = { x: b.x - ux * head, y: b.y - uy * head };
  const shaft = polyline([a, base]);
  const tip = polyline([b, { x: base.x - uy * head * 0.55, y: base.y + ux * head * 0.55 }, { x: base.x + uy * head * 0.55, y: base.y - ux * head * 0.55 }], true);
  const body = (l: CanvasRenderingContext2D) => {
    stroke(l, shaft, css(color), { width, cap: "round", dash: dashed ? [7, 5] : [] });
    fill(l, tip, css(color));
  };
  if (glow) layer(ctx, dpr, body, { shadow: { color: opacity(color, 0.75), radius: 6 } });
  else layer(ctx, dpr, body);
}

function small(ctx: CanvasRenderingContext2D, s: string, at: Pt, color: RGBA, anchor: Anchor = "center"): void {
  if (s === "") return;
  drawText(ctx, s, SMALL, color, at, anchor);
}

function coil(ctx: CanvasRenderingContext2D, dpr: number, a: Pt, b: Pt, coils: number, amplitude: number, color: RGBA): void {
  const d = Math.hypot(b.x - a.x, b.y - a.y);
  if (!(d > 1)) return;
  const ux = (b.x - a.x) / d;
  const uy = (b.y - a.y) / d;
  const nx = -uy;
  const ny = ux;
  const lead = d * 0.08;
  const body = d - 2 * lead;
  const count = Math.max(3, coils) * 2;
  const pts: Pt[] = [a, { x: a.x + ux * lead, y: a.y + uy * lead }];
  for (let k = 1; k <= count; k++) {
    const s = lead + (body * k) / (count + 1);
    const side = k % 2 === 0 ? -1 : 1;
    pts.push({ x: a.x + ux * s + nx * amplitude * side, y: a.y + uy * s + ny * amplitude * side });
  }
  pts.push({ x: b.x - ux * lead, y: b.y - uy * lead }, b);
  layer(ctx, dpr, (l) => stroke(l, polyline(pts), css(color), { width: 2.5, cap: "round", join: "round" }), { shadow: { color: opacity(color, 0.5), radius: 4 } });
}

function plot(ctx: CanvasRenderingContext2D, dpr: number, item: MGItem, vp: Viewport, theme: Theme, color: RGBA, p: number): void {
  const o = item.pts[0];
  if (!o) return;
  const w = n(item, "w");
  const h = n(item, "h");
  const tl = vp.point(add(o, P(0, h)));
  const frame = rect(tl.x, tl.y, vp.length(w), vp.length(h));
  fill(ctx, roundedRect(frame, 6), css(opacity(theme.labelFill, 0.5)));
  const g = new Path2D();
  for (let k = 1; k < 4; k++) {
    const fx = minX(frame) + (frame.w * k) / 4;
    const fy = minY(frame) + (frame.h * k) / 4;
    g.moveTo(fx, minY(frame));
    g.lineTo(fx, maxY(frame));
    g.moveTo(minX(frame), fy);
    g.lineTo(maxX(frame), fy);
  }
  stroke(ctx, g, css(opacity(theme.grid, 1.5)), { width: 1 });
  stroke(ctx, roundedRect(frame, 6), css(opacity(theme.subtleInk, 0.5)), { width: 1 });
  const x0 = n(item, "x0");
  const x1 = n(item, "x1");
  const y0 = n(item, "y0");
  const y1 = n(item, "y1");
  const mapped = item.pts.slice(1).map((q) => ({
    x: minX(frame) + frame.w * ((q.x - x0) / (x1 - x0)),
    y: maxY(frame) - frame.h * ((q.y - y0) / (y1 - y0)),
  }));
  ctx.save();
  const clip = inset(frame, -2, -2)!;
  ctx.beginPath();
  ctx.rect(clip.x, clip.y, clip.w, clip.h);
  ctx.clip();
  layer(ctx, dpr, (l) => stroke(l, polyline(trimPolyline(mapped, p)), css(color), { width: 2.8, cap: "round", join: "round" }),
    { shadow: { color: opacity(color, 0.7), radius: 5 } });
  ctx.restore();
  const f = (v: number) => format(v, "");
  small(ctx, f(x0), { x: minX(frame), y: maxY(frame) + 9 }, theme.subtleInk, "leading");
  small(ctx, f(x1), { x: maxX(frame), y: maxY(frame) + 9 }, theme.subtleInk, "trailing");
  small(ctx, f(y1), { x: minX(frame) - 4, y: minY(frame) + 6 }, theme.subtleInk, "trailing");
  small(ctx, f(y0), { x: minX(frame) - 4, y: maxY(frame) - 6 }, theme.subtleInk, "trailing");
  if (item.list.length === 2) {
    small(ctx, item.list[0], { x: midX(frame), y: maxY(frame) + 22 }, theme.subtleInk);
    small(ctx, item.list[1], { x: minX(frame) + 6, y: minY(frame) - 10 }, theme.subtleInk, "leading");
  }
}

function bars(ctx: CanvasRenderingContext2D, dpr: number, item: MGItem, vp: Viewport, theme: Theme, p: number): void {
  const o = item.pts[0];
  if (!o || item.bars.length === 0) return;
  const w = vp.length(n(item, "w"));
  const h = vp.length(n(item, "h"));
  const origin = vp.point(o); // bottom-left
  const frame = rect(origin.x, origin.y - h, w, h);
  fill(ctx, roundedRect(inset(frame, -8, -8)!, 12), css(opacity(theme.labelFill, 0.6)));
  const top = Math.max(Math.max(...item.bars.map((b) => Math.abs(b.value))), 1e-9);
  const labelBand = 18;
  const valueBand = 18;
  const usable = h - labelBand - valueBand - (item.label === undefined ? 0 : 18);
  const baseline = maxY(frame) - labelBand;
  const slot = w / item.bars.length;
  const bw = slot * 0.56;
  stroke(ctx, polyline([{ x: minX(frame), y: baseline }, { x: maxX(frame), y: baseline }]), css(opacity(theme.subtleInk, 0.6)), { width: 1 });
  item.bars.forEach((b, k) => {
    const c = roleColor(theme, b.color);
    const x = minX(frame) + slot * k + (slot - bw) / 2;
    const bh = Math.max(0, usable * (Math.abs(b.value) / top) * p);
    const r = rect(x, baseline - bh, bw, bh);
    layer(ctx, dpr, (l) => fill(l, roundedRect(r, Math.min(6, bw / 3)), linearGradient(l, [c, opacity(c, 0.55)], { x: 0, y: minY(r) }, { x: 0, y: maxY(r) })),
      { shadow: { color: opacity(c, 0.55), radius: 6 } });
    small(ctx, b.label, { x: x + bw / 2, y: baseline + 10 }, theme.subtleInk);
    small(ctx, format(b.value, item.text ?? ""), { x: x + bw / 2, y: baseline - bh - 9 }, theme.ink);
  });
  if (item.label !== undefined) drawText(ctx, item.label, { size: 13, weight: "bold" }, theme.ink, { x: minX(frame) + 2, y: minY(frame) + 6 }, "leading");
}

/** Equal-size cells from the top-left corner, each row fading in after the one above. */
function table(ctx: CanvasRenderingContext2D, dpr: number, item: MGItem, vp: Viewport, theme: Theme, color: RGBA, p: number,
  emphasisRows: Set<number>, emphasisCells: Set<number>): void {
  const c = item.pts[0];
  if (!c) return;
  const rawRows = n(item, "rows", 1);
  const rawCols = n(item, "cols", 1);
  if (!(rawRows >= 1 && rawRows <= MGLimits.tableRows) || !(rawCols >= 1 && rawCols <= MGLimits.tableCols)) return;
  const rows = Math.trunc(rawRows);
  const cols = Math.trunc(rawCols);
  const cw = n(item, "cw", 1.6);
  const rh = n(item, "rh", 0.7);
  const topLeft = vp.point(add(c, P((-cw * cols) / 2, (rh * rows) / 2)));
  const w = vp.length(cw);
  const h = vp.length(rh);
  const marked = new Set(item.marked);
  for (let r = 0; r < rows; r++) {
    const appearRow = Math.min(1, Math.max(0, p * rows - r * 0.6));
    if (!(appearRow > 0)) continue;
    ctx.save();
    ctx.globalAlpha = appearRow;
    const header = r === 0 && item.flags.has("header");
    for (let k = 0; k < cols; k++) {
      const i = r * cols + k;
      if (i >= item.list.length) continue;
      const cell = rect(topLeft.x + w * k, topLeft.y + h * r, w, h);
      const fillColor = marked.has(i) ? opacity(roleColor(theme, "good"), 0.4) : header ? opacity(color, 0.28) : opacity(color, 0.07);
      fill(ctx, rectPath(inset(cell, 1, 1) ?? cell), css(fillColor));
      stroke(ctx, rectPath(cell), css(opacity(theme.subtleInk, 0.45)), { width: 1 });
      const size = Math.max(10, Math.min(16, h * 0.42));
      drawText(ctx, item.list[i], { size, weight: header ? "bold" : "medium", design: "rounded" }, theme.ink, { x: midX(cell), y: midY(cell) });
    }
    ctx.restore();
  }
  // One rounded border around the whole grid, faded with the draw-on progress.
  stroke(ctx, roundedRect(rect(topLeft.x, topLeft.y, w * cols, h * rows), 4), css(opacity(color, 0.8 * p)), { width: 1.5 });
  const glow = roleColor(theme, "yellow");
  const boxes: Rect[] = [...emphasisRows].sort((a, b) => a - b).filter((r) => r < rows).map((r) => rect(topLeft.x, topLeft.y + h * r, w * cols, h));
  boxes.push(...[...emphasisCells].sort((a, b) => a - b).filter((i) => i < rows * cols)
    .map((i) => rect(topLeft.x + w * (i % cols), topLeft.y + h * Math.trunc(i / cols), w, h)));
  for (const box of boxes) {
    layer(ctx, dpr, (l) => stroke(l, roundedRect(inset(box, -2, -2)!, 5), css(opacity(glow, 0.95 * p)), { width: 2.5 }),
      { shadow: { color: opacity(glow, 0.9), radius: 8 } });
  }
}

function array(ctx: CanvasRenderingContext2D, dpr: number, item: MGItem, vp: Viewport, theme: Theme, color: RGBA, p: number): void {
  const c = item.pts[0];
  if (!c) return;
  const cell = n(item, "cell", 1);
  const count = item.list.length;
  const side = vp.length(cell);
  const left = vp.point(sub(c, P((cell * count) / 2, 0)));
  const marked = new Set(item.marked);
  item.list.forEach((v, k) => {
    const appearCell = Math.min(1, Math.max(0, p * count - k * 0.6));
    if (!(appearCell > 0)) return;
    const r = rect(left.x + side * k + 2, left.y - side / 2 + 2, side - 4, side - 4);
    const f = marked.has(k) ? roleColor(theme, "good") : color;
    ctx.save();
    ctx.globalAlpha = appearCell;
    fill(ctx, roundedRect(r, 8), css(opacity(f, marked.has(k) ? 0.45 : 0.18)));
    stroke(ctx, roundedRect(r, 8), css(opacity(f, 0.9)), { width: 1.8 });
    drawText(ctx, v, { size: Math.max(11, Math.min(20, side * 0.38)), weight: "bold", design: "rounded" }, theme.ink, { x: midX(r), y: midY(r) });
    small(ctx, String(k), { x: midX(r), y: minY(r) - 9 }, opacity(theme.subtleInk, 0.8));
    ctx.restore();
  });
  // Pointers below their cell; several on one cell stack downward.
  const stack = new Map<number, number>();
  const accent = roleColor(theme, "yellow");
  for (const ptr of item.pointers) {
    const slot = Math.round(ptr.index);
    const level = stack.get(slot) ?? 0;
    stack.set(slot, level + 1);
    const x = left.x + side * (ptr.index + 0.5);
    const y = left.y + side / 2 + 6 + level * 22;
    const tri = polyline([{ x, y }, { x: x - 7, y: y + 10 }, { x: x + 7, y: y + 10 }], true);
    layer(ctx, dpr, (l) => fill(l, tri, css(accent)), { shadow: { color: opacity(accent, 0.8), radius: 5 } });
    drawText(ctx, ptr.label, { size: 12, weight: "heavy", design: "rounded" }, accent, { x: x + 14, y: y + 6 }, "leading");
  }
}

/** Convenience used by the browser entry point: the settled frame of `scene` at `step` and `time`. */
export type { MGPoint };
