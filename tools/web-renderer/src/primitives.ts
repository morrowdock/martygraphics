// SPDX-License-Identifier: Apache-2.0
// Port of the `MGParser` primitives (Sources/MartyGraphics/MGParser.swift, "MARK: primitives"): closed key sets,
// finite ranges, identifiers, points, ranges and the plain-text sanitizer with `{name}` placeholders.

import { fail } from "./errors.js";
import { format } from "./format.js";
import { type JSONObject, type JSONValue, isObject } from "./json.js";
import type { MGPoint, MGValue } from "./model.js";
import { P, length, mul } from "./model.js";
import {
  characterCount, characterIsASCII, characterIsLetter, characterIsWhitespace, graphemes, isControlScalar,
  isNewlineScalar, isWhitespaceOrNewlineScalar, scalarCount, swiftStringCompare, trimScalars,
} from "./unicode.js";

/** Context shared by item parsing, edits and patches (`MGContext`). */
export interface Ctx {
  width: number;
  height: number;
  is3D: boolean;
  values: Record<string, MGValue>;
}

export const span = (ctx: Ctx): number => Math.max(ctx.width, ctx.height);

/** Closed range test (`ClosedRange.contains`). */
export const inRange = (d: number, lo: number, hi: number): boolean => d >= lo && d <= hi;

/** `MGParser.closed`: required keys first (`.missing`), then unknown keys (`.unknown.a,b`, sorted, all of them). */
export function closed(o: JSONObject, required: Iterable<string>, optional: Iterable<string>, what: string): void {
  const keys = Object.keys(o);
  const req = new Set(required);
  for (const r of req) if (!keys.includes(r)) fail(`${what}.missing`);
  const allowed = new Set([...req, ...optional]);
  const unknown = keys.filter((k) => !allowed.has(k));
  if (unknown.length) fail(`${what}.unknown.${unknown.sort(swiftStringCompare).join(",")}`);
}

/** `MGParser.num`: a finite JSON number in the closed range. Booleans are not numbers. */
export function num(v: JSONValue | undefined, lo: number, hi: number, what: string): number {
  if (typeof v !== "number" || !Number.isFinite(v) || !inRange(v, lo, hi)) fail(what);
  return v;
}

/** `MGParser.identifier`: 1–24 ASCII letters, digits or `_`, starting with a letter. */
export function identifier(v: JSONValue | undefined, what: string): string {
  if (typeof v !== "string" || !/^[A-Za-z][A-Za-z0-9_]{0,23}$/.test(v)) fail(what);
  return v;
}

/** `MGParser.point`: `[x, y]` (or `[x, y, z]` in 3D) inside the world's ±25% margin. */
export function point(v: JSONValue | undefined, ctx: Ctx, what: string): MGPoint {
  if (!Array.isArray(v) || !(v.length === 2 || (v.length === 3 && ctx.is3D))) fail(what);
  const x = num(v[0], -0.25 * ctx.width, 1.25 * ctx.width, what);
  const y = num(v[1], -0.25 * ctx.height, 1.25 * ctx.height, what);
  const z = v.length === 3 ? num(v[2], -span(ctx), span(ctx), what) : 0;
  return P(x, y, z);
}

/** `MGParser.vector3`: unit direction, components in -1...1, length over 0.01, normalised. */
export function vector3(v: JSONValue | undefined, what: string): MGPoint {
  if (!Array.isArray(v) || v.length !== 3) fail(what);
  const p = P(num(v[0], -1, 1, what), num(v[1], -1, 1, what), num(v[2], -1, 1, what));
  const l = length(p);
  if (!(l > 0.01)) fail(what);
  return Math.abs(l - 1) < 1e-9 ? p : mul(p, 1 / l);
}

/** `MGParser.dataPoint`: plot samples in ±1e6. */
export function dataPoint(v: JSONValue | undefined, what: string): MGPoint {
  if (!Array.isArray(v) || v.length !== 2) fail(what);
  return P(num(v[0], -1e6, 1e6, what), num(v[1], -1e6, 1e6, what));
}

/** `MGParser.range`: `[lo, hi]` in ±1e6 with lo < hi. */
export function range(v: JSONValue | undefined, what: string): [number, number] {
  if (!Array.isArray(v) || v.length !== 2) fail(what);
  const lo = num(v[0], -1e6, 1e6, what);
  const hi = num(v[1], -1e6, 1e6, what);
  if (!(lo < hi)) fail(what);
  return [lo, hi];
}

/** True when `<` is directly followed by a letter, `/`, `!` or `?` and a `>` comes later (`looksLikeMarkup`). */
export function looksLikeMarkup(s: string): boolean {
  const c = graphemes(s);
  for (let i = 0; i < c.length; i++) {
    if (c[i] !== "<" || i + 1 >= c.length) continue;
    const next = c[i + 1];
    if ((characterIsLetter(next) || next === "/" || next === "!" || next === "?") && c.slice(i + 1).includes(">")) return true;
  }
  return false;
}

/**
 * `MGParser.text`: short plain text with `{name}` placeholders filled from computed values. Rejects markup, code
 * fences, URLs, control characters (Cc, Cf; a line feed is allowed) and unknown placeholders. The scalar limit
 * applies to the untrimmed text; the stored text is trimmed (code text keeps leading spaces).
 */
export function text(v: JSONValue | undefined, max: number, ctx: Ctx, what: string, code = false): string {
  if (typeof v !== "string") fail(what);
  const s = v;
  const t = trimScalars(s, code ? isNewlineScalar : isWhitespaceOrNewlineScalar);
  const ok =
    t !== "" &&
    !(code && graphemes(t).every(characterIsWhitespace)) &&
    scalarCount(s) <= max &&
    (code ? !looksLikeMarkup(s) : !s.includes("<") && !s.includes(">")) &&
    !s.includes("```") &&
    !s.includes("://") &&
    !Array.from(s).some((ch) => isControlScalar(ch) && ch !== "\n");
  if (!ok) fail(what);
  return fill(t, ctx.values, what);
}

/** `MGParser.fill`: replaces `{name}` (1–16 ASCII letters or digits) with the formatted value. */
export function fill(s: string, values: Record<string, MGValue>, what: string): string {
  if (!s.includes("{") && !s.includes("}")) return s;
  let out = "";
  let name = "";
  let inside = false;
  for (const ch of graphemes(s)) {
    if (inside) {
      if (ch === "}") {
        if (characterCount(name) > 16 || name.includes("_")) fail(`${what}.placeholder`);
        const v = Object.prototype.hasOwnProperty.call(values, name) ? values[name] : undefined;
        if (!v) fail(`${what}.placeholder.${name}`);
        out += format(v.value, v.unit);
        name = "";
        inside = false;
      } else {
        if (!(characterIsASCII(ch) && /^[A-Za-z0-9]$/.test(ch) && characterCount(name) < 16)) fail(`${what}.placeholder`);
        name += ch;
      }
    } else if (ch === "{") inside = true;
    else if (ch === "}") fail(`${what}.brace`);
    else out += ch;
  }
  if (inside) fail(`${what}.brace`);
  return out;
}

export function objectValue(v: JSONValue | undefined): JSONObject | undefined {
  return isObject(v) ? v : undefined;
}
