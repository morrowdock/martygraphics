// SPDX-License-Identifier: Apache-2.0
// Port of `MGLimits` (Sources/MartyGraphics/MGParser.swift). Everything outside them is rejected, never clamped.

export const MGLimits = {
  sceneBytes: 8 * 1024,
  patchBytes: 4 * 1024,
  items: 24,
  templateExtras: 10,
  resolvedItems: 40,
  steps: 8,
  stepEdits: 6,
  templateSteps: 48,
  showPerStep: 16,
  overrides: 16,
  hide: 16,
  label: 40,
  text: 120,
  say: 200,
  title: 60,
  points: 64,
  ropePoints: 6,
  cells: 16,
  cellText: 6,
  pointers: 4,
  bars: 6,
  barLabel: 16,
  nodeText: 8,
  worldMin: 2,
  worldMax: 100,
  records: 32,
  recordFields: 6,
  rawParamsBytes: 4 * 1024,
  depth: 64,
  tableRows: 8,
  tableCols: 6,
  tableCellText: 12,
} as const;

/** `SceneValidator.maximumInputBytes` (tools/SceneValidator): the raw input bound of the Swift CLI. */
export const maximumInputBytes = MGLimits.sceneBytes * 2;
