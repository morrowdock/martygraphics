// SPDX-License-Identifier: Apache-2.0
// Canvas 2D stand-ins for the SwiftUI `GraphicsContext` features MGCanvasRenderer uses: paths with draw-on trimming,
// layers with a shadow filter and opacity, gradients, and `Text` measured and drawn at an anchor.
//
// Text: SwiftUI draws SF Pro (system), SF Pro Rounded and SF Mono. A browser uses whatever the font stack below
// resolves to (Segoe UI and Consolas on Windows; the SF faces on macOS). Line boxes use SF Pro's vertical metrics so
// boxes and baselines land where SwiftUI puts them; glyph widths come from the browser's font. See README "Known gaps".

import { type Rect, rect } from "./layout.js";
import { type RGBA, css } from "./theme.js";

export type Pt = { x: number; y: number };

// MARK: shadow calibration

/**
 * Canvas `shadowBlur` per SwiftUI shadow-filter radius. Canvas blur b is a Gaussian with sigma b/2, so 2 means
 * sigma = radius (the CALayer shadowRadius convention). Chosen by sweeping 0–2.5 against the 14 PNG boards in
 * docs/assets/native (the seven Showcase stills and the seven 500×270 boards of overview.png;
 * `node scripts/parity-native.mjs --calibrate`): 2 gave the lowest mean error. `render` in browser.ts may override it
 * for one call and restores it afterwards.
 */
export let SHADOW_BLUR_PER_RADIUS = 2.0;
export function setShadowBlurPerRadius(k: number): void {
  SHADOW_BLUR_PER_RADIUS = k;
}

// MARK: paths

export function polyline(points: Pt[], closed = false): Path2D {
  const p = new Path2D();
  points.forEach((q, i) => (i === 0 ? p.moveTo(q.x, q.y) : p.lineTo(q.x, q.y)));
  if (closed) p.closePath();
  return p;
}

/** `Path.trimmedPath(from: 0, to: t)` for an open polyline. */
export function trimPolyline(points: Pt[], t: number): Pt[] {
  if (t >= 1 || points.length < 2) return points;
  if (t <= 0) return [points[0]];
  let total = 0;
  for (let i = 1; i < points.length; i++) total += Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y);
  let left = total * t;
  const out = [points[0]];
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    const seg = Math.hypot(b.x - a.x, b.y - a.y);
    if (seg >= left) {
      const f = seg > 0 ? left / seg : 0;
      out.push({ x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f });
      return out;
    }
    out.push(b);
    left -= seg;
  }
  return out;
}

export function ellipse(r: Rect, trim = 1): Path2D {
  const p = new Path2D();
  const sweep = Math.max(0, Math.min(1, trim)) * Math.PI * 2;
  p.ellipse(r.x + r.w / 2, r.y + r.h / 2, r.w / 2, r.h / 2, 0, 0, sweep);
  if (trim >= 1) p.closePath();
  return p;
}

export function roundedRect(r: Rect, radius: number): Path2D {
  const p = new Path2D();
  const rr = Math.max(0, Math.min(radius, r.w / 2, r.h / 2));
  p.roundRect(r.x, r.y, r.w, r.h, rr);
  return p;
}

export function rectPath(r: Rect): Path2D {
  const p = new Path2D();
  p.rect(r.x, r.y, r.w, r.h);
  return p;
}

// MARK: layers

let scratch: HTMLCanvasElement | null = null;

function scratchFor(main: HTMLCanvasElement): CanvasRenderingContext2D {
  if (!scratch) scratch = document.createElement("canvas");
  if (scratch.width !== main.width || scratch.height !== main.height) {
    scratch.width = main.width;
    scratch.height = main.height;
  }
  const l = scratch.getContext("2d")!;
  l.setTransform(1, 0, 0, 1, 0, 0);
  l.clearRect(0, 0, scratch.width, scratch.height);
  return l;
}

/**
 * `ctx.drawLayer { l in l.addFilter(.shadow(...)); l.opacity = ... }`: draws into an isolated layer, then composites
 * it once (so the shadow is cast by the whole layer, as in SwiftUI) under the current clip.
 */
export function layer(ctx: CanvasRenderingContext2D, dpr: number, draw: (l: CanvasRenderingContext2D) => void,
  opts: { shadow?: { color: RGBA; radius: number }; opacity?: number } = {}): void {
  const l = scratchFor(ctx.canvas);
  l.setTransform(ctx.getTransform());
  draw(l);
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.globalAlpha = ctx.globalAlpha * (opts.opacity ?? 1);
  if (opts.shadow) {
    ctx.shadowColor = css(opts.shadow.color);
    ctx.shadowBlur = opts.shadow.radius * SHADOW_BLUR_PER_RADIUS * dpr;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
  }
  ctx.drawImage(l.canvas, 0, 0);
  ctx.restore();
}

// MARK: fills and strokes

export function fill(ctx: CanvasRenderingContext2D, path: Path2D, style: string | CanvasGradient): void {
  ctx.fillStyle = style;
  ctx.fill(path);
}

export interface StrokeStyle {
  width: number;
  cap?: CanvasLineCap;
  join?: CanvasLineJoin;
  dash?: number[];
}

export function stroke(ctx: CanvasRenderingContext2D, path: Path2D, style: string, s: StrokeStyle): void {
  ctx.save();
  ctx.strokeStyle = style;
  ctx.lineWidth = s.width;
  ctx.lineCap = s.cap ?? "butt";
  ctx.lineJoin = s.join ?? "miter";
  ctx.setLineDash(s.dash ?? []);
  ctx.stroke(path);
  ctx.restore();
}

export function linearGradient(ctx: CanvasRenderingContext2D, colors: RGBA[], from: Pt, to: Pt): CanvasGradient {
  const g = ctx.createLinearGradient(from.x, from.y, to.x, to.y);
  colors.forEach((c, i) => g.addColorStop(colors.length === 1 ? 0 : i / (colors.length - 1), css(c)));
  return g;
}

export function radialGradient(ctx: CanvasRenderingContext2D, colors: RGBA[], center: Pt, startRadius: number, endRadius: number): CanvasGradient {
  const g = ctx.createRadialGradient(center.x, center.y, Math.max(0, startRadius), center.x, center.y, Math.max(0.0001, endRadius));
  colors.forEach((c, i) => g.addColorStop(colors.length === 1 ? 0 : i / (colors.length - 1), css(c)));
  return g;
}

// MARK: text

export type Weight = "regular" | "medium" | "semibold" | "bold" | "heavy";
export type Design = "default" | "rounded" | "monospaced";

export interface TextStyle {
  size: number;
  weight: Weight;
  design?: Design;
}

const WEIGHTS: Record<Weight, number> = { regular: 400, medium: 500, semibold: 600, bold: 700, heavy: 800 };

export const FONT_STACKS: Record<Design, string> = {
  default: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
  rounded: 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
  monospaced: 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Cascadia Mono", "Liberation Mono", monospace',
};

/** SF Pro vertical metrics (hhea ascender 1950, descender 494, line gap 0 per 2048 units). */
const ASCENT = 1950 / 2048;
const DESCENT = 494 / 2048;
export const lineHeight = (size: number) => (ASCENT + DESCENT) * size;

export function font(style: TextStyle): string {
  return `${WEIGHTS[style.weight]} ${style.size}px ${FONT_STACKS[style.design ?? "default"]}`;
}

/**
 * Pixel grid for measured text sizes. SwiftUI reports `Text.measure` sizes rounded up to the display's pixel grid:
 * the Swift captures show a 13 pt label box 24 pt tall (15.5 pt of SF Pro line height, rounded up to 16, plus 8).
 * Set per frame from the device pixel ratio.
 */
let pixelGrid = 1;
export function setPixelGrid(dpr: number): void {
  pixelGrid = dpr > 0 ? dpr : 1;
}
const ceilToGrid = (v: number) => Math.ceil(v * pixelGrid - 1e-6) / pixelGrid;

export interface TextLayout {
  lines: string[];
  widths: number[];
  width: number;
  height: number;
}

/** Lines of `s` (explicit line feeds, then greedy word wrap when `maxWidth` is given) and their size. */
export function layoutText(ctx: CanvasRenderingContext2D, s: string, style: TextStyle, maxWidth?: number): TextLayout {
  ctx.save();
  ctx.font = font(style);
  const lines: string[] = [];
  for (const para of s.split("\n")) {
    if (maxWidth === undefined || ctx.measureText(para).width <= maxWidth) {
      lines.push(para);
      continue;
    }
    let line = "";
    for (const word of para.split(" ")) {
      const candidate = line === "" ? word : line + " " + word;
      if (ctx.measureText(candidate).width <= maxWidth || line === "") {
        if (line === "" && ctx.measureText(word).width > maxWidth) {
          // Break an over-long word by characters.
          let chunk = "";
          for (const ch of Array.from(word)) {
            if (chunk !== "" && ctx.measureText(chunk + ch).width > maxWidth) {
              lines.push(chunk);
              chunk = ch;
            } else chunk += ch;
          }
          line = chunk;
        } else line = candidate;
      } else {
        lines.push(line);
        line = word;
      }
    }
    lines.push(line);
  }
  const widths = lines.map((l) => ctx.measureText(l.replace(/\s+$/u, "")).width);
  ctx.restore();
  return { lines, widths, width: ceilToGrid(Math.max(0, ...widths)), height: ceilToGrid(lines.length * lineHeight(style.size)) };
}

export type Anchor = "center" | "leading" | "trailing";

/** `ctx.draw(Text, at: point, anchor:)`: the text block's anchor point lands on `at`; lines are leading-aligned. */
export function drawText(ctx: CanvasRenderingContext2D, s: string, style: TextStyle, color: RGBA, at: Pt, anchor: Anchor = "center"): TextLayout {
  const t = layoutText(ctx, s, style);
  const left = anchor === "center" ? at.x - t.width / 2 : anchor === "leading" ? at.x : at.x - t.width;
  drawLines(ctx, t, style, color, rect(left, at.y - t.height / 2, t.width, t.height));
  return t;
}

/** `ctx.draw(Text, in: rect)`: wraps at the rect's width, first line at the top. */
export function drawTextIn(ctx: CanvasRenderingContext2D, s: string, style: TextStyle, color: RGBA, r: Rect): void {
  drawLines(ctx, layoutText(ctx, s, style, r.w), style, color, r);
}

function drawLines(ctx: CanvasRenderingContext2D, t: TextLayout, style: TextStyle, color: RGBA, r: Rect): void {
  ctx.save();
  ctx.font = font(style);
  ctx.fillStyle = css(color);
  ctx.textAlign = "left";
  ctx.textBaseline = "alphabetic";
  const lh = lineHeight(style.size);
  t.lines.forEach((line, i) => ctx.fillText(line, r.x, r.y + i * lh + ASCENT * style.size));
  ctx.restore();
}
