// SPDX-License-Identifier: Apache-2.0
// Port of the template contract (Sources/MartyGraphics/MGTemplates.swift): declared parameters, `validate` with the
// parser's reasons, `build` with reason normalisation, and the registry (core built-ins plus opt-in packs).

import { MGError, fail } from "./errors.js";
import { type JSONObject, type JSONValue, has } from "./json.js";
import type { MGCamera, MGItem, MGStep, MGValue } from "./model.js";
import { num } from "./primitives.js";

export interface ParamField {
  name: string;
  range: [number, number];
  integer: boolean;
}

export interface ParamSpec {
  name: string;
  unit: string;
  range: [number, number];
  /** `Infinity` means optional (absent stays Infinity). */
  defaultValue?: number;
  integer?: boolean;
  /** Number lists and record lists: allowed element count. */
  count?: [number, number];
  /** Record lists only. */
  fields?: ParamField[];
  listDefault?: number[];
}

export interface Params {
  numbers: Record<string, number>;
  lists: Record<string, number[]>;
  records: Record<string, number[][]>;
}

export const param = (p: Params, key: string): number => p.numbers[key] ?? 0;

export interface TemplateBuild {
  title: string;
  width: number;
  height: number;
  items: MGItem[];
  steps: MGStep[];
  values: Record<string, MGValue>;
  camera?: MGCamera;
}

export interface Template {
  name: string;
  summary: string;
  params: ParamSpec[];
  check?: (p: Params) => boolean;
  reject?: (p: Params) => string | null;
  make: (p: Params, is3D: boolean) => TemplateBuild | null;
}

const RESERVED_FIELDS = new Set(["arity", "count", "integer", "missing", "spec"]);
const declName = (s: string) => /^[a-z][a-z0-9_]{0,15}$/.test(s);

function listValueOK(spec: ParamSpec, d: number[]): boolean {
  return d.every((x) => Number.isFinite(x) && x >= spec.range[0] && x <= spec.range[1] && (!spec.integer || Math.round(x) === x));
}

function recordDeclarationProblem(spec: ParamSpec): string | null {
  const fields = spec.fields;
  if (!fields) return null;
  if (!declName(spec.name)) return "name";
  if (!spec.count) return "count";
  if (spec.count[0] < 0 || spec.count[1] > 32) return "count";
  if (fields.length < 1 || fields.length > 6) return "fields";
  const seen = new Set<string>();
  for (const f of fields) {
    if (!declName(f.name) || RESERVED_FIELDS.has(f.name) || seen.has(f.name)) return "field";
    seen.add(f.name);
    if (!Number.isFinite(f.range[0]) || !Number.isFinite(f.range[1])) return "field";
  }
  return null;
}

/** `MGTemplate.suffixOK`: lowercase ASCII words joined by dots, at most 48 scalars. */
export function suffixOK(suffix: string): boolean {
  if (Array.from(suffix).length > 48) return false;
  const parts = suffix.split(".");
  return parts.length > 0 && parts.every((part) => /^[a-z][a-z0-9_]*$/.test(part));
}

const rejection = (suffix: string): string => (suffixOK(suffix) ? `template.${suffix}` : "template.check");

/** `MGTemplate.thrownReason`. */
export function thrownReason(reason: string): string {
  if (!reason.startsWith("template.")) return "template.build";
  return suffixOK(reason.slice("template.".length)) ? reason : "template.build";
}

function records(spec: ParamSpec, value: JSONValue | undefined): number[][] {
  const fields = spec.fields!;
  if (recordDeclarationProblem(spec) !== null || !spec.count) fail(`template.${spec.name}.spec`);
  const count = spec.count;
  let list: JSONValue[];
  if (Array.isArray(value)) list = value;
  else if (value === undefined && count[0] === 0) list = [];
  else if (value === undefined) fail(`template.${spec.name}.missing`);
  else fail(`template.${spec.name}`);
  if (list.length < count[0] || list.length > count[1]) fail(`template.${spec.name}.count`);
  return list.map((record) => {
    if (!Array.isArray(record) || record.length !== fields.length) fail(`template.${spec.name}.arity`);
    return fields.map((field, k) => {
      const d = num(record[k], field.range[0], field.range[1], `template.${spec.name}.${field.name}`);
      if (field.integer && Math.round(d) !== d) fail(`template.${spec.name}.${field.name}.integer`);
      return d;
    });
  });
}

/** `MGTemplate.validate`: checks a `params` object exactly as the parser does. */
export function validateParams(t: Template, raw: JSONObject): Params {
  const names = new Set(t.params.map((s) => s.name));
  for (const k of Object.keys(raw)) if (!names.has(k)) fail("template.params.unknown");
  const out: Params = { numbers: Object.create(null), lists: Object.create(null), records: Object.create(null) };
  for (const spec of t.params) {
    const v = has(raw, spec.name) ? raw[spec.name] : undefined;
    if (spec.fields) {
      out.records[spec.name] = records(spec, v);
    } else if (spec.count) {
      if (v === undefined && spec.listDefault) {
        if (spec.listDefault.length < spec.count[0] || spec.listDefault.length > spec.count[1] || !listValueOK(spec, spec.listDefault)) {
          fail(`template.${spec.name}.default`);
        }
        out.lists[spec.name] = [...spec.listDefault];
        continue;
      }
      if (!Array.isArray(v) || v.length < spec.count[0] || v.length > spec.count[1]) fail(`template.${spec.name}`);
      out.lists[spec.name] = v.map((e) => {
        const d = num(e, spec.range[0], spec.range[1], `template.${spec.name}`);
        if (spec.integer && Math.round(d) !== d) fail(`template.${spec.name}.integer`);
        return d;
      });
    } else if (v !== undefined) {
      const d = num(v, spec.range[0], spec.range[1], `template.${spec.name}`);
      if (spec.integer && Math.round(d) !== d) fail(`template.${spec.name}.integer`);
      out.numbers[spec.name] = d;
    } else if (spec.defaultValue !== undefined) {
      out.numbers[spec.name] = spec.defaultValue;
    } else {
      fail(`template.${spec.name}.missing`);
    }
  }
  const why = t.reject?.(out) ?? null;
  if (why !== null) fail(rejection(why));
  if (t.check && !t.check(out)) fail("template.check");
  return out;
}

/** `MGTemplate.build`: thrown reasons are normalised; anything that is not an `MGError` is `template.build`. */
export function buildTemplate(t: Template, p: Params, is3D: boolean): TemplateBuild | null {
  try {
    return t.make(p, is3D);
  } catch (e) {
    if (e instanceof MGError) throw new MGError(thrownReason(e.reason));
    throw new MGError("template.build");
  }
}

// MARK: registry

const core: Template[] = [];
const packs = new Map<string, Template[]>();

export function registerCore(t: Template): void {
  core.push(t);
}

export function registerPack(id: string, templates: Template[]): void {
  packs.set(id, templates);
}

/** Names of the opt-in packs this build ships (`graphs`). */
export function knownPacks(): string[] {
  return [...packs.keys()];
}

/** `MGTemplates.library` with the given opt-in packs registered (core first; the first template with a name wins). */
export function library(enabled: readonly string[]): Map<string, Template> {
  const lib = new Map<string, Template>();
  for (const t of core) if (!lib.has(t.name)) lib.set(t.name, t);
  for (const id of enabled) for (const t of packs.get(id) ?? []) if (!lib.has(t.name)) lib.set(t.name, t);
  return lib;
}
