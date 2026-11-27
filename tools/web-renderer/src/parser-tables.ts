// SPDX-License-Identifier: Apache-2.0
// The per-kind key tables of `MGParser` (Sources/MartyGraphics/MGParser.swift, `allowedKeys`, `required`,
// `defaultColor`) and the scene's top-level keys.

import type { MGColorRole, MGKind } from "./model.js";

export const TOP_KEYS = ["v", "template", "params", "title", "dim", "world", "items", "steps", "camera", "hide", "over"];

const COMMON = ["id", "k", "color"];

const EXTRA: Record<MGKind, string[]> = {
  body: ["at", "shape", "size", "angle", "label", "move"],
  incline: ["at", "base", "angle", "label"],
  line: ["from", "to", "style"],
  vector: ["from", "on", "angle", "dir", "len", "label", "dashed"],
  axes: ["at", "w", "h", "xl", "yl"],
  plot: ["at", "w", "h", "xr", "yr", "pts", "xl", "yl", "label"],
  spring: ["from", "to", "coils", "label"],
  pulley: ["at", "r"],
  rope: ["pts"],
  orbit: ["at", "r", "label"],
  text: ["at", "text", "style"],
  highlight: ["target", "label"],
  bars: ["at", "w", "h", "bars", "unit", "label"],
  path: ["pts", "dashed"],
  array: ["at", "vals", "cell", "ptrs", "marked", "label"],
  node: ["at", "text", "r"],
  edge: ["a", "b", "dir", "label"],
  table: ["at", "cells", "header", "cw", "rh", "marked", "label"],
  region: ["pts", "dashed", "label"],
};

const REQUIRED: Record<MGKind, string[]> = {
  body: ["at"],
  incline: ["at", "base", "angle"],
  line: ["from", "to"],
  spring: ["from", "to"],
  vector: ["len"],
  axes: ["at", "w", "h"],
  plot: ["at", "w", "h", "xr", "yr", "pts"],
  pulley: ["at", "r"],
  orbit: ["at", "r"],
  rope: ["pts"],
  path: ["pts"],
  text: ["at", "text"],
  highlight: ["target"],
  bars: ["at", "w", "h", "bars"],
  array: ["at", "vals"],
  node: ["at", "text"],
  edge: ["a", "b"],
  table: ["at", "cells"],
  region: ["pts"],
};

export function allowedKeys(kind: MGKind): Set<string> {
  return new Set([...COMMON, ...EXTRA[kind]]);
}

export function requiredKeys(kind: MGKind): Set<string> {
  return new Set(REQUIRED[kind]);
}

export function defaultColor(kind: MGKind): MGColorRole {
  switch (kind) {
    case "body": return "blue";
    case "vector": return "force";
    case "spring": return "teal";
    case "text": case "axes": case "line": case "pulley": case "rope": case "edge": return "muted";
    case "highlight": return "yellow";
    case "plot": case "path": return "accent";
    case "orbit": return "purple";
    case "bars": return "energy";
    case "incline": return "muted";
    case "array": case "node": return "blue";
    case "table": case "region": return "accent";
  }
}
