// SPDX-License-Identifier: Apache-2.0
// Port of the scene model (Sources/MartyGraphics/MGModel.swift). World coordinates: x right, y UP, origin
// bottom-left. Pure values; `MGParser` is the only producer of items.

import type { JSONValue } from "./json.js";
import { isWhitespaceOrNewlineScalar, trimScalars } from "./unicode.js";

export interface MGPoint {
  x: number;
  y: number;
  z: number;
}

export const P = (x: number, y: number, z = 0): MGPoint => ({ x, y, z });
export const add = (a: MGPoint, b: MGPoint): MGPoint => P(a.x + b.x, a.y + b.y, a.z + b.z);
export const sub = (a: MGPoint, b: MGPoint): MGPoint => P(a.x - b.x, a.y - b.y, a.z - b.z);
export const mul = (a: MGPoint, s: number): MGPoint => P(a.x * s, a.y * s, a.z * s);
export const length = (a: MGPoint): number => Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
export const lerp = (a: MGPoint, b: MGPoint, t: number): MGPoint => add(a, mul(sub(b, a), t));
/** Unit vector at `degrees` counter-clockwise from +x in the xy plane, times `r`. */
export const polar = (degrees: number, r = 1): MGPoint => {
  const a = (degrees * Math.PI) / 180;
  return P(Math.cos(a) * r, Math.sin(a) * r);
};

/** The 22 semantic colour roles, in `MGColorRole.allCases` order. */
export const COLOR_ROLES = [
  "force", "normal", "friction", "gravity", "tension", "velocity", "accel", "energy", "kinetic", "potential",
  "accent", "muted", "good", "warn", "blue", "red", "green", "orange", "purple", "yellow", "teal", "white",
] as const;
export type MGColorRole = (typeof COLOR_ROLES)[number];
export const isColorRole = (s: string): s is MGColorRole => (COLOR_ROLES as readonly string[]).includes(s);

/** The 19 item kinds, in `MGKind.allCases` order. */
export const KINDS = [
  "body", "incline", "line", "vector", "axes", "plot", "spring", "pulley", "rope", "orbit", "text", "highlight",
  "bars", "path", "array", "node", "edge", "table", "region",
] as const;
export type MGKind = (typeof KINDS)[number];
export const isKind = (s: string): s is MGKind => (KINDS as readonly string[]).includes(s);
/** Kinds the 3D renderer draws (`MGKind.in3D`). */
export const KINDS_3D: ReadonlySet<MGKind> = new Set(["body", "incline", "line", "vector", "axes", "orbit", "text", "highlight", "path"]);

export interface MGBar {
  label: string;
  value: number;
  color: MGColorRole;
}

export interface MGPointer {
  /** Cell index as a number so pointer moves can animate between cells. */
  index: number;
  label: string;
}

export interface MGItem {
  id: string;
  kind: MGKind;
  /** at | from,to | polyline points, depending on kind. */
  pts: MGPoint[];
  /** Numeric properties (size, angle, len, r, w, h, ...), validated per kind. Null-prototype record. */
  num: Record<string, number>;
  label?: string;
  text?: string;
  color: MGColorRole;
  /** body id for `vector.on`, target for `highlight`, node ids for `edge`. */
  ref?: string;
  ref2?: string;
  /** ball, dashed, ground, callout, title, code, dir, dir3, header */
  flags: Set<string>;
  /** array cell values, table cells (row-major) or axis labels [x, y]. */
  list: string[];
  bars: MGBar[];
  pointers: MGPointer[];
  marked: number[];
  /** 3D direction for vectors in 3D scenes. */
  dir?: MGPoint;
}

export function newItem(id: string, kind: MGKind, color: MGColorRole): MGItem {
  return {
    id, kind, pts: [], num: Object.create(null) as Record<string, number>, color,
    flags: new Set(), list: [], bars: [], pointers: [], marked: [],
  };
}

export function cloneItem(i: MGItem): MGItem {
  const num = Object.create(null) as Record<string, number>;
  for (const k of Object.keys(i.num)) num[k] = i.num[k];
  return {
    ...i,
    pts: i.pts.map((p) => ({ ...p })),
    num,
    flags: new Set(i.flags),
    list: [...i.list],
    bars: i.bars.map((b) => ({ ...b })),
    pointers: i.pointers.map((p) => ({ ...p })),
    marked: [...i.marked],
    dir: i.dir ? { ...i.dir } : undefined,
  };
}

/** `MGItem.n(key, fallback)`. */
export function n(i: MGItem, key: string, fallback = 0): number {
  const v = i.num[key];
  return v === undefined ? fallback : v;
}

/**
 * True for a table with no data row (`MGItem.isEmptyTable`): every cell after the header row is empty or white
 * space. Renderers do not draw it.
 */
export function isEmptyTable(i: MGItem): boolean {
  if (i.kind !== "table") return false;
  const rows = n(i, "rows", 1);
  const cols = n(i, "cols", 1);
  if (!Number.isFinite(rows) || !Number.isFinite(cols) || rows < 1 || cols < 1 || Math.round(rows) !== rows ||
    Math.round(cols) !== cols || i.list.length !== rows * cols) return false;
  const skip = i.flags.has("header") ? cols : 0;
  return i.list.slice(skip).every((c) => trimScalars(c, isWhitespaceOrNewlineScalar) === "");
}

export interface MGCamera {
  x?: number;
  y?: number;
  zoom: number;
  yaw: number;
  pitch: number;
}

export interface MGEdit {
  id: string;
  key: string;
  value: JSONValue;
}

export interface MGStep {
  say: string;
  show: string[];
  focus?: string;
  camera?: MGCamera;
  /** Applied cumulatively when moving forward. */
  edits: MGEdit[];
}

export interface MGValue {
  value: number;
  unit: string;
}

export interface MGScene {
  /** Canonical JSON of the validated wire scene; patches rewrite it and re-validate from scratch. */
  source: JSONValue;
  template?: string;
  title: string;
  is3D: boolean;
  width: number;
  height: number;
  items: MGItem[];
  steps: MGStep[];
  camera?: MGCamera;
  values: Record<string, MGValue>;
  /** Template motion. None of the shipped templates (bst, two_pointers, shortest_path) has one. */
  motion: "none";
  attachments: Record<string, string>;
  /** Step to open on (a patch can jump to a step). */
  startStep: number;
  /** Number of patches applied. */
  revision: number;
  /** Opt-in packs the scene was parsed with, so patches re-parse with the same registry. */
  packs: readonly string[];
}

export function sceneItem(scene: MGScene, id: string): MGItem | undefined {
  return scene.items.find((i) => i.id === id);
}

/** `MGScene.animates`. */
export function animates(scene: MGScene): boolean {
  return scene.items.some((i) => i.num["moveT"] !== undefined);
}
