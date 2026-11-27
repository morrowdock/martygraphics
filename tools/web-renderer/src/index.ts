// SPDX-License-Identifier: Apache-2.0
// Public surface of the prototype. Parsing and validation run in Node or a browser; drawing needs a canvas.

export { MGError } from "./errors.js";
export { MGLimits, maximumInputBytes } from "./limits.js";
export { canonicalByteCount, decodeJSONBytes, parseJSONText, spellNumber } from "./json.js";
export { format, formatFixed } from "./format.js";
export { parseScene, parseSceneBytes, item, wire, apply } from "./parser.js";
export { applyPatch, parsePatch, parsePatchBytes } from "./patch.js";
export { checkSceneBytes } from "./validator.js";
export type { Outcome } from "./validator.js";
export { itemsAtStep, frame, firstShown, spring, cycle } from "./timeline.js";
export { Viewport, bounds, place, textSize, shaftStart } from "./layout.js";
export { loadScene, prepareFrame, resolveStep } from "./frame.js";
export { draw } from "./renderer.js";
export { board as boardTheme } from "./theme.js";
export { knownPacks } from "./templates.js";
export { COLOR_ROLES, KINDS } from "./model.js";
export type { MGScene, MGItem, MGStep } from "./model.js";
