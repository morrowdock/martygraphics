// SPDX-License-Identifier: Apache-2.0
// The byte-level front door of `MGParser.scene(data:)` and the `MGJSON` value model
// (Sources/MartyGraphics/MGModel.swift): UTF-8 only, no NUL byte, textual nesting counted before any parse, a strict
// RFC 8259 decoder, finite numbers only, and the canonical (sorted-key, compact) byte count used by the size limits.
//
// Objects are null-prototype records, so a key such as "__proto__" is an ordinary own key and can never reach a
// prototype. Duplicate keys and a byte-order mark are refused with `json` (fail closed; the Python preflight does the
// same). Swift's behaviour for them is not measured, so both stay outside the parity claim (README "Parity" and
// "Known gaps").

export type JSONValue = null | boolean | number | string | JSONValue[] | JSONObject;
export interface JSONObject {
  [key: string]: JSONValue;
}

export function isObject(v: JSONValue | undefined): v is JSONObject {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function newObject(entries?: Iterable<[string, JSONValue]>): JSONObject {
  const o = Object.create(null) as JSONObject;
  if (entries) for (const [k, v] of entries) o[k] = v;
  return o;
}

export function has(o: JSONObject, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(o, key);
}

export function get(o: JSONObject, key: string): JSONValue | undefined {
  return has(o, key) ? o[key] : undefined;
}

/** Deep equality of two JSON values (Swift `MGJSON ==`): numbers compare by value, objects by key set. */
export function jsonEqual(a: JSONValue | undefined, b: JSONValue | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  if (a === null || b === null) return a === b;
  if (typeof a !== typeof b) return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (!jsonEqual(a[i], b[i])) return false;
    return true;
  }
  if (Array.isArray(b)) return false;
  if (typeof a === "object" && typeof b === "object") {
    const ka = Object.keys(a);
    const kb = Object.keys(b as JSONObject);
    if (ka.length !== kb.length) return false;
    for (const k of ka) {
      if (!has(b as JSONObject, k) || !jsonEqual(a[k], (b as JSONObject)[k])) return false;
    }
    return true;
  }
  return a === b;
}

export class JSONSyntaxError extends Error {}

/** `MGJSON.textNesting`: arrays and objects on one path, counted without parsing; brackets in strings do not count. */
export function textNesting(text: string): number {
  let depth = 0;
  let deepest = 0;
  let inString = false;
  let escape = false;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (inString) {
      if (escape) escape = false;
      else if (c === 0x5c) escape = true;
      else if (c === 0x22) inString = false;
      continue;
    }
    if (c === 0x22) inString = true;
    else if (c === 0x7b || c === 0x5b) {
      depth++;
      if (depth > deepest) deepest = depth;
    } else if (c === 0x7d || c === 0x5d) depth--;
  }
  return deepest;
}

const fatalDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/** UTF-8 text of `bytes`, or null when the bytes hold a NUL or are not valid UTF-8 (`MGJSON.utf8Nesting`). */
export function utf8Text(bytes: Uint8Array): string | null {
  if (bytes.includes(0)) return null;
  try {
    return fatalDecoder.decode(bytes);
  } catch {
    return null;
  }
}

/** Locate the first repeated key before syntax decoding, as MGKeyScanner does. */
function duplicateKeyPath(text: string): string | undefined {
  type Frame = { keys: Set<string>; key?: string; expectKey: boolean } | { index: number };
  const frames: Frame[] = [];
  const tokens = /("(?:[^"\\]|\\[\s\S])*")|"[\s\S]*$|[{}\[\],]/g;
  const segment = (key: string) => Array.from(key).slice(0, 32).join("").replace(/[^A-Za-z0-9_]/gu, "_") || "_";
  for (const [token, quoted] of text.matchAll(tokens)) {
    const top = frames.at(-1);
    if (token === "{") frames.push({ keys: new Set(), expectKey: true });
    else if (token === "[") frames.push({ index: 0 });
    else if (token === "}" || token === "]") frames.pop();
    else if (token === "," && top) {
      if ("keys" in top) top.expectKey = true;
      else top.index++;
    } else if (quoted && top && "keys" in top && top.expectKey) {
      const raw = token.slice(1, -1);
      let key = raw;
      if (raw.includes("\\")) {
        try {
          const decoded: string = JSON.parse(token);
          if (!/[\uD800-\uDFFF]/u.test(decoded)) key = decoded;
        } catch { /* Keep the original spelling for an invalid escape. */ }
      }
      const normalized = key.normalize("NFC");
      if (top.keys.has(normalized)) {
        return frames.map((frame) => "keys" in frame
          ? segment(frame === top ? key : frame.key ?? "") : String(frame.index)).join(".");
      }
      top.keys.add(normalized);
      top.key = key;
      top.expectKey = false;
    }
  }
}

/**
 * `MGJSON.dataRefusal` followed by the system parser and `MGJSON(any:)`. Returns the decoded value or the refusal
 * reason: `jsonReason` for invalid UTF-8 or JSON, `depthReason` for excess textual nesting, and the scoped
 * duplicate-key reason when supplied by the scene decoder.
 */
export function decodeJSONBytes(bytes: Uint8Array, depthReason: string, jsonReason = "json", duplicatePrefix?: string):
  { ok: true; value: JSONValue } | { ok: false; reason: string } {
  const text = utf8Text(bytes);
  if (text === null) return { ok: false, reason: jsonReason };
  if (textNesting(text) > 64) return { ok: false, reason: depthReason };
  if (duplicatePrefix !== undefined) {
    const duplicate = duplicateKeyPath(text);
    if (duplicate !== undefined) return { ok: false, reason: duplicatePrefix + duplicate };
  }
  try {
    return { ok: true, value: parseJSONText(text) };
  } catch {
    return { ok: false, reason: jsonReason };
  }
}

/** Strict RFC 8259 decoder. Top level must be an object or an array (JSONSerialization without fragments). */
export function parseJSONText(text: string): JSONValue {
  let i = 0;
  const n = text.length;
  const err = (why: string): never => {
    throw new JSONSyntaxError(`${why} at ${i}`);
  };
  const ws = () => {
    while (i < n) {
      const c = text.charCodeAt(i);
      if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d) i++;
      else break;
    }
  };
  const parseString = (): string => {
    // text[i] === '"'
    i++;
    let out = "";
    let start = i;
    while (true) {
      if (i >= n) err("unterminated string");
      const c = text.charCodeAt(i);
      if (c === 0x22) {
        out += text.slice(start, i);
        i++;
        break;
      }
      if (c < 0x20) err("control character in string");
      if (c === 0x5c) {
        out += text.slice(start, i);
        i++;
        if (i >= n) err("bad escape");
        const e = text[i];
        switch (e) {
          case '"': out += '"'; break;
          case "\\": out += "\\"; break;
          case "/": out += "/"; break;
          case "b": out += "\b"; break;
          case "f": out += "\f"; break;
          case "n": out += "\n"; break;
          case "r": out += "\r"; break;
          case "t": out += "\t"; break;
          case "u": {
            const hex = text.slice(i + 1, i + 5);
            if (!/^[0-9a-fA-F]{4}$/.test(hex)) err("bad unicode escape");
            const code = parseInt(hex, 16);
            i += 4;
            if (code >= 0xd800 && code <= 0xdbff) {
              // A high surrogate must be followed by an escaped low surrogate.
              const next = text.slice(i + 1, i + 7);
              if (!/^\\u[dD][c-fC-F][0-9a-fA-F]{2}$/.test(next)) err("lone surrogate");
              out += String.fromCharCode(code, parseInt(next.slice(2), 16));
              i += 6;
            } else if (code >= 0xdc00 && code <= 0xdfff) {
              err("lone surrogate");
            } else {
              out += String.fromCharCode(code);
            }
            break;
          }
          default:
            err("bad escape");
        }
        i++;
        start = i;
        continue;
      }
      i++;
    }
    return out;
  };
  const numberRE = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y;
  const parseValue = (): JSONValue => {
    ws();
    if (i >= n) err("unexpected end");
    const c = text[i];
    if (c === "{") {
      i++;
      const o = newObject();
      ws();
      if (text[i] === "}") {
        i++;
        return o;
      }
      while (true) {
        ws();
        if (text[i] !== '"') err("expected key");
        const key = parseString();
        ws();
        if (text[i] !== ":") err("expected colon");
        i++;
        const value = parseValue();
        if (has(o, key)) err("duplicate key");
        o[key] = value;
        ws();
        if (text[i] === ",") {
          i++;
          continue;
        }
        if (text[i] === "}") {
          i++;
          return o;
        }
        err("expected , or }");
      }
    }
    if (c === "[") {
      i++;
      const a: JSONValue[] = [];
      ws();
      if (text[i] === "]") {
        i++;
        return a;
      }
      while (true) {
        a.push(parseValue());
        ws();
        if (text[i] === ",") {
          i++;
          continue;
        }
        if (text[i] === "]") {
          i++;
          return a;
        }
        err("expected , or ]");
      }
    }
    if (c === '"') return parseString();
    if (text.startsWith("true", i)) {
      i += 4;
      return true;
    }
    if (text.startsWith("false", i)) {
      i += 5;
      return false;
    }
    if (text.startsWith("null", i)) {
      i += 4;
      return null;
    }
    numberRE.lastIndex = i;
    const m = numberRE.exec(text);
    if (!m || m[0].length === 0) return err("unexpected character");
    i += m[0].length;
    const d = Number(m[0]);
    // MGJSON(any:) refuses a non-finite number (an overflowing literal such as 1e400): the scene reason is `json`.
    if (!Number.isFinite(d)) err("non-finite number");
    return d;
  };
  ws();
  if (i >= n) err("empty");
  if (text[i] !== "{" && text[i] !== "[") err("top level must be an object or an array");
  const v = parseValue();
  ws();
  if (i !== n) err("trailing content");
  return v;
}

// MARK: canonical size

/**
 * Number spelling used for the canonical byte count. Whole numbers use integer digits; others use the shortest
 * round-trip digits, with an exponent (two digits at least) below 1e-4, as Python's `repr` and Swift's `description`
 * do. This mirrors the Python preflight; see README "Known gaps" for the Swift caveat.
 */
export function spellNumber(x: number): string {
  if (Number.isInteger(x)) return BigInt(x).toString();
  const exp = x.toExponential(); // shortest round-trip digits, e.g. "1.25e-7"
  const [mant, e] = exp.split("e");
  const power = Number(e);
  const negative = mant.startsWith("-");
  const digits = mant.replace("-", "").replace(".", "");
  const decpt = power + 1;
  let body: string;
  if (decpt <= -4 || decpt > 16) {
    const ee = Math.abs(power).toString().padStart(2, "0");
    body = (digits.length > 1 ? digits[0] + "." + digits.slice(1) : digits) + "e" + (power < 0 ? "-" : "+") + ee;
  } else if (decpt <= 0) {
    body = "0." + "0".repeat(-decpt) + digits;
  } else if (decpt >= digits.length) {
    body = digits + "0".repeat(decpt - digits.length);
  } else {
    body = digits.slice(0, decpt) + "." + digits.slice(decpt);
  }
  return (negative ? "-" : "") + body;
}

const encoder = new TextEncoder();
function stringBytes(s: string): number {
  // JSONSerialization / json.dumps escaping: quote, backslash and C0 controls; everything else is raw UTF-8.
  return encoder.encode(JSON.stringify(s)).length;
}

/** Bytes of the compact, sorted-key canonical encoding (`MGJSON.canonicalByteCount`). Depth is bounded by 64. */
export function canonicalByteCount(v: JSONValue): number {
  if (v === null) return 4;
  if (v === true) return 4;
  if (v === false) return 5;
  if (typeof v === "number") return spellNumber(v).length;
  if (typeof v === "string") return stringBytes(v);
  if (Array.isArray(v)) {
    let total = 2 + Math.max(0, v.length - 1);
    for (const e of v) total += canonicalByteCount(e);
    return total;
  }
  const keys = Object.keys(v);
  let total = 2 + Math.max(0, keys.length - 1);
  for (const k of keys) total += stringBytes(k) + 1 + canonicalByteCount(v[k]);
  return total;
}

/** Nesting of a value built in code (`MGJSON.measure().depth`), iteratively. */
export function valueDepth(v: JSONValue): number {
  let deepest = 0;
  const stack: Array<[JSONValue, number]> = [[v, 0]];
  while (stack.length) {
    const [x, level] = stack.pop()!;
    if (Array.isArray(x)) {
      deepest = Math.max(deepest, level + 1);
      for (const e of x) stack.push([e, level + 1]);
    } else if (isObject(x)) {
      deepest = Math.max(deepest, level + 1);
      for (const k of Object.keys(x)) stack.push([x[k], level + 1]);
    }
  }
  return deepest;
}

/** True when every number is finite (`MGJSON.measure().finite`). */
export function allFinite(v: JSONValue): boolean {
  const stack: JSONValue[] = [v];
  while (stack.length) {
    const x = stack.pop()!;
    if (typeof x === "number" && !Number.isFinite(x)) return false;
    if (Array.isArray(x)) stack.push(...x);
    else if (isObject(x)) for (const k of Object.keys(x)) stack.push(x[k]);
  }
  return true;
}

/** `MGJSON.checkEntry`: number, then depth, then canonical bytes. */
export function checkEntry(v: JSONValue, maxDepth: number, maxBytes: number, reasons: { number: string; depth: string; bytes: string }): string | null {
  if (!allFinite(v)) return reasons.number;
  if (valueDepth(v) > maxDepth) return reasons.depth;
  if (canonicalByteCount(v) > maxBytes) return reasons.bytes;
  return null;
}

/** Compact sorted-key JSON text, for display and for passing a validated value along. */
export function canonicalString(v: JSONValue): string {
  if (v === null || typeof v !== "object") return JSON.stringify(v);
  if (Array.isArray(v)) return "[" + v.map(canonicalString).join(",") + "]";
  const keys = Object.keys(v).sort();
  return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonicalString(v[k])).join(",") + "}";
}

/** Deep copy into null-prototype objects (for values built in code). */
export function cloneJSON(v: JSONValue): JSONValue {
  if (Array.isArray(v)) return v.map(cloneJSON);
  if (isObject(v)) return newObject(Object.keys(v).map((k) => [k, cloneJSON(v[k])] as [string, JSONValue]));
  return v;
}
