// SPDX-License-Identifier: Apache-2.0
// The two core built-in templates (Sources/MartyGraphics/MGTemplates.swift, `MGTemplates.all`): `bst` and
// `two_pointers`. Everything they produce is re-validated by the parser with the wire rules, as in Swift.

import { MGError } from "./errors.js";
import { format } from "./format.js";
import { type JSONValue, newObject } from "./json.js";
import { type MGColorRole, type MGEdit, type MGItem, type MGKind, type MGPoint, type MGStep, type MGValue, P, newItem } from "./model.js";
import { defaultColor } from "./parser-tables.js";
import { fill } from "./primitives.js";
import { type Template, param, registerCore } from "./templates.js";
import { MGLimits } from "./limits.js";

// MARK: MGMake

export function makeKind(id: string, kind: MGKind, pts: MGPoint[], num: Record<string, number> = {}, color?: MGColorRole, label?: string): MGItem {
  const i = newItem(id, kind, color ?? defaultColor(kind));
  i.pts = pts;
  for (const k of Object.keys(num)) i.num[k] = num[k];
  if (label !== undefined) i.label = label;
  return i;
}

export function makeText(id: string, at: MGPoint, text: string, style?: string, color: MGColorRole = "white"): MGItem {
  const i = newItem(id, "text", color);
  i.pts = [at];
  i.text = text;
  if (style) i.flags.add(style);
  return i;
}

export function step(say: string, opts: { show?: string[]; focus?: string; edits?: MGEdit[] } = {}): MGStep {
  return { say, show: opts.show ?? [], focus: opts.focus, edits: opts.edits ?? [] };
}

/** `MGMake.say`: fills placeholders from the template's values, keeping the raw text if that fails. */
export function say(s: string, values: Record<string, MGValue>, opts: { show?: string[]; focus?: string } = {}): MGStep {
  let filled = s;
  try {
    filled = fill(s, values, "template");
  } catch (e) {
    if (!(e instanceof MGError)) throw e;
  }
  return step(filled, opts);
}

// MARK: Binary search tree

export const bst: Template = {
  name: "bst",
  summary: "insert values into a binary search tree in order; optional find path",
  params: [
    { name: "values", unit: "", range: [-999, 999], integer: true, count: [1, 15] },
    { name: "find", unit: "", range: [-999, 999], defaultValue: Infinity, integer: false },
  ],
  check: (p) => {
    const values = p.lists["values"] ?? [];
    return new Set(values).size === values.length;
  },
  make: (p) => {
    const values = p.lists["values"] ?? [];
    const left = new Map<number, number>();
    const right = new Map<number, number>();
    const depth: number[] = [0];
    for (let i = 1; i < Math.max(values.length, 1); i++) {
      let at = 0;
      let d = 1;
      while (true) {
        if (values[i] < values[at]) {
          const l = left.get(at);
          if (l !== undefined) { at = l; d += 1; } else { left.set(at, i); break; }
        } else {
          const r = right.get(at);
          if (r !== undefined) { at = r; d += 1; } else { right.set(at, i); break; }
        }
      }
      depth.push(d);
    }
    const maxDepth = Math.max(0, ...depth);
    if (maxDepth > 6) return null;
    const order = values.map((_, i) => i).sort((a, b) => values[a] - values[b]);
    const dx = values.length > 1 ? 10.4 / (values.length - 1) : 0;
    const dy = maxDepth > 0 ? Math.min(1.4, 5.8 / maxDepth) : 0;
    const pos = new Map<number, MGPoint>();
    order.forEach((i, rank) => pos.set(i, P(values.length > 1 ? 0.8 + rank * dx : 6, 7 - depth[i] * dy)));
    let items: MGItem[] = [];
    values.forEach((v, i) => {
      const node = makeKind(`n${i}`, "node", [pos.get(i)!], { r: 0.42 });
      node.text = format(v, "");
      items.push(node);
    });
    const edges: Array<[number, number]> = [...left.entries(), ...right.entries()];
    edges.sort((a, b) => a[1] - b[1]);
    for (const [parent, child] of edges) {
      const e = newItem(`e${child}`, "edge", "muted");
      e.ref = `n${parent}`;
      e.ref2 = `n${child}`;
      items.push(e);
    }
    // Swift `items.sort { $0.kind == .edge && $1.kind != .edge }` (stable): edges first, then nodes.
    items = [...items.filter((i) => i.kind === "edge"), ...items.filter((i) => i.kind !== "edge")];
    const v: Record<string, MGValue> = { n: { value: values.length, unit: "" }, height: { value: maxDepth, unit: "" } };
    const steps: MGStep[] = [say("Insert in order. Smaller goes left, bigger or equal goes right. Height {height}.", v, { focus: "n0" })];
    const target = param(p, "find");
    if (Number.isFinite(target)) {
      let at: number | undefined = 0;
      let k = 0;
      while (at !== undefined && k < 6) {
        const node: number = at;
        const value: number = values[node];
        const h = newItem(`h${k}`, "highlight", "yellow");
        h.ref = `n${node}`;
        items.push(h);
        const a = format(target, "");
        const b = format(value, "");
        if (value === target) {
          steps.push(step(`${a} = ${b}. Found it in ${k + 1} comparisons.`, { show: [`h${k}`], focus: `n${node}` }));
          break;
        }
        const goLeft: boolean = target < value;
        steps.push(step(`${a} is ${goLeft ? "smaller" : "bigger"} than ${b}, so go ${goLeft ? "left" : "right"}.`, { show: [`h${k}`], focus: `n${node}` }));
        at = goLeft ? left.get(node) : right.get(node);
        k += 1;
        if (at === undefined) {
          steps.push(step(`Nothing there: ${a} isn't in the tree.`));
          break;
        }
      }
    }
    return { title: "Binary search tree", width: 12, height: 8, items, steps: steps.slice(0, MGLimits.templateSteps), values: v };
  },
};

// MARK: Two pointers on a sorted array

export const twoPointers: Template = {
  name: "two_pointers",
  summary: "sorted array pair-sum with L/R pointers moving step by step",
  params: [
    { name: "vals", unit: "", range: [-999, 999], integer: true, count: [2, 12] },
    { name: "target", unit: "", range: [-1998, 1998], integer: true },
  ],
  check: (p) => {
    const a = p.lists["vals"] ?? [];
    for (let i = 1; i < a.length; i++) if (!(a[i - 1] <= a[i])) return false;
    return true;
  },
  make: (p) => {
    const a = p.lists["vals"] ?? [];
    const target = param(p, "target");
    const arr = makeKind("arr", "array", [P(6, 4)], { cell: Math.min(0.9, 10.5 / a.length) });
    arr.list = a.map((d) => format(d, ""));
    arr.pointers = [{ index: 0, label: "L" }, { index: a.length - 1, label: "R" }];
    const ptrs = (l: number, r: number): JSONValue => [
      newObject([["i", l], ["label", "L"]]),
      newObject([["i", r], ["label", "R"]]),
    ];
    const f = (d: number) => format(d, "");
    const steps: MGStep[] = [step(`Find two numbers that add to ${f(target)}. Start L at the smallest, R at the largest.`, { focus: "arr" })];
    let l = 0;
    let r = a.length - 1;
    while (l < r && steps.length < MGLimits.templateSteps - 1) {
      const sum = a[l] + a[r];
      if (sum === target) {
        steps.push(step(`${f(a[l])} + ${f(a[r])} = ${f(sum)}. Found the pair.`, { focus: "arr", edits: [{ id: "arr", key: "marked", value: [l, r] }] }));
        break;
      }
      const small = sum < target;
      if (small) l += 1; else r -= 1;
      steps.push(step(
        `${f(a[small ? l - 1 : l])} + ${f(a[small ? r : r + 1])} = ${f(sum)} is too ${small ? "small, so move L right" : "big, so move R left"}.`,
        { focus: "arr", edits: [{ id: "arr", key: "ptrs", value: ptrs(l, r) }] },
      ));
    }
    if (l >= r && steps.length < MGLimits.templateSteps) steps.push(step(`The pointers met: no pair adds to ${f(target)}.`));
    const v: Record<string, MGValue> = { target: { value: target, unit: "" } };
    return {
      title: "Two pointers", width: 12, height: 8,
      items: [arr, makeText("goal", P(6, 6.6), `target ${f(target)}`, "callout", "warn")],
      steps, values: v,
    };
  },
};

registerCore(bst);
registerCore(twoPointers);
