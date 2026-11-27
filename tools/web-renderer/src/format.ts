// SPDX-License-Identifier: Apache-2.0
// Port of `MGPhysics.format` (Sources/MartyGraphics/MGPhysics.swift). `String(format: "%.Nf")` rounds the exact
// binary value and breaks exact ties to even (C printf); JavaScript's `toFixed` breaks ties away from zero, so the
// fixed-point step is done here with exact integer arithmetic instead.

const view = new DataView(new ArrayBuffer(8));

/** printf("%.{digits}f", v) for a finite double, with round-half-even on exact ties. */
export function formatFixed(v: number, digits: number): string {
  const negative = v < 0 || Object.is(v, -0);
  const a = Math.abs(v);
  view.setFloat64(0, a);
  const hi = view.getUint32(0);
  const lo = view.getUint32(4);
  const exponentBits = (hi >>> 20) & 0x7ff;
  let mantissa = (BigInt(hi & 0xfffff) << 32n) | BigInt(lo);
  let exponent: number;
  if (exponentBits === 0) {
    exponent = -1074; // subnormal or zero
  } else {
    mantissa |= 1n << 52n;
    exponent = exponentBits - 1075;
  }
  // a = mantissa * 2^exponent; scaled = a * 10^digits
  const scale = 10n ** BigInt(digits);
  let q: bigint;
  if (exponent >= 0) {
    q = mantissa * scale * (1n << BigInt(exponent));
  } else {
    const num = mantissa * scale;
    const den = 1n << BigInt(-exponent);
    q = num / den;
    const r2 = (num % den) * 2n;
    if (r2 > den || (r2 === den && (q & 1n) === 1n)) q += 1n;
  }
  let s = q.toString();
  if (digits > 0) {
    s = s.padStart(digits + 1, "0");
    s = s.slice(0, s.length - digits) + "." + s.slice(s.length - digits);
  }
  return (negative ? "-" : "") + s;
}

/** Plain label numbers: about 3 significant figures, no scientific notation, no trailing zeros. */
export function format(v: number, unit: string): string {
  if (!Number.isFinite(v)) return "—";
  const a = Math.abs(v);
  const digits = a >= 100 ? 0 : a >= 10 ? 1 : 2;
  let s = formatFixed(v, digits);
  if (s.includes(".")) {
    while (s.endsWith("0")) s = s.slice(0, -1);
    if (s.endsWith(".")) s = s.slice(0, -1);
  }
  if (s === "-0") s = "0";
  return unit === "" ? s : unit === "°" ? s + unit : s + " " + unit;
}
