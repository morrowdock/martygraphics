// SPDX-License-Identifier: Apache-2.0
// Port of `MGError` (Sources/MartyGraphics/MGParser.swift). The reason is a developer code for tests and logs only.

export class MGError extends Error {
  readonly reason: string;
  constructor(reason: string) {
    super(reason);
    this.reason = reason;
    this.name = "MGError";
  }
}

/** Throw an `MGError` with `reason`. Typed `never` so it can end a guard expression. */
export function fail(reason: string): never {
  throw new MGError(reason);
}

/** Result shape shared by every entry point: `{ ok: true, value }` or `{ ok: false, reason }`. */
export type Result<T> = { ok: true; value: T } | { ok: false; reason: string };

export function capture<T>(fn: () => T, unknown = "unknown"): Result<T> {
  try {
    return { ok: true, value: fn() };
  } catch (e) {
    if (e instanceof MGError) return { ok: false, reason: e.reason };
    return { ok: false, reason: unknown };
  }
}
