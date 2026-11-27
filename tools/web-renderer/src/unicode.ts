// SPDX-License-Identifier: Apache-2.0
// Foundation `CharacterSet` and Swift `Character` predicates used by the parser, emulated with Unicode property
// escapes. Swift counts `String.count` in grapheme clusters and `unicodeScalars.count` in code points; this module
// keeps the two apart the same way. See README "Known gaps" for the places where ICU and Swift can disagree.

const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

/** Swift `Array(string)`: extended grapheme clusters. */
export function graphemes(s: string): string[] {
  const out: string[] = [];
  for (const g of segmenter.segment(s)) out.push(g.segment);
  return out;
}

/** Swift `string.count`. */
export function characterCount(s: string): number {
  let n = 0;
  for (const _ of segmenter.segment(s)) n++;
  return n;
}

/** Swift `string.unicodeScalars.count`. */
export function scalarCount(s: string): number {
  let n = 0;
  for (const _ of s) n++;
  return n;
}

/** First `n` unicode scalars of `s` (Swift `String(String.UnicodeScalarView(s.unicodeScalars.prefix(n)))`). */
export function scalarPrefix(s: string, n: number): string {
  let out = "";
  let k = 0;
  for (const ch of s) {
    if (k++ >= n) break;
    out += ch;
  }
  return out;
}

const controlRE = /[\p{Cc}\p{Cf}]/u;
/** `CharacterSet.controlCharacters`: General Category Cc and Cf. */
export function isControlScalar(ch: string): boolean {
  return controlRE.test(ch);
}

const whitespaceAndNewlineRE = /^[\p{Zs}\t\n\v\f\r\x85\u{2028}\u{2029}]$/u;
/** `CharacterSet.whitespacesAndNewlines`: Zs, U+0009, U+000A–U+000D, U+0085, U+2028, U+2029. */
export function isWhitespaceOrNewlineScalar(ch: string): boolean {
  return whitespaceAndNewlineRE.test(ch);
}

/** `CharacterSet.newlines`: U+000A–U+000D, U+0085, U+2028, U+2029. */
export function isNewlineScalar(ch: string): boolean {
  const c = ch.codePointAt(0) ?? -1;
  return (c >= 0x0a && c <= 0x0d) || c === 0x85 || c === 0x2028 || c === 0x2029;
}

/** `String.trimmingCharacters(in:)`: drops leading and trailing unicode scalars that satisfy `inSet`. */
export function trimScalars(s: string, inSet: (ch: string) => boolean): string {
  const scalars = Array.from(s);
  let a = 0;
  let b = scalars.length;
  while (a < b && inSet(scalars[a])) a++;
  while (b > a && inSet(scalars[b - 1])) b--;
  return scalars.slice(a, b).join("");
}

const whiteSpacePropRE = /^\p{White_Space}/u;
/** Swift `Character.isWhitespace`: the first scalar has the White_Space property. */
export function characterIsWhitespace(g: string): boolean {
  return whiteSpacePropRE.test(g);
}

const alphabeticRE = /^\p{Alphabetic}/u;
/** Swift `Character.isLetter`: the first scalar is Alphabetic. */
export function characterIsLetter(g: string): boolean {
  return alphabeticRE.test(g);
}

/** Swift `Character.isASCII` (a single ASCII scalar, or CR LF). */
export function characterIsASCII(g: string): boolean {
  return /^[\x00-\x7f]$/.test(g) || g === "\r\n";
}

/** Swift `String <` on keys for the closed-key reason: NFC-normalised unicode scalar order. */
export function swiftStringCompare(a: string, b: string): number {
  const x = Array.from(a.normalize("NFC"), (c) => c.codePointAt(0) ?? 0);
  const y = Array.from(b.normalize("NFC"), (c) => c.codePointAt(0) ?? 0);
  const n = Math.min(x.length, y.length);
  for (let i = 0; i < n; i++) if (x[i] !== y[i]) return x[i] - y[i];
  return x.length - y.length;
}

const encoder = new TextEncoder();
export function utf8Length(s: string): number {
  return encoder.encode(s).length;
}
