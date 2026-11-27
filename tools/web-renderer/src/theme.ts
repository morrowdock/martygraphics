// SPDX-License-Identifier: Apache-2.0
// Port of `MGTheme.board` (Sources/MartyGraphics/MGTheme.swift): the dark "lab board" and the 22 role colours.

import type { MGColorRole } from "./model.js";

export interface RGBA {
  r: number;
  g: number;
  b: number;
  a: number;
}

const hex = (v: number): RGBA => ({ r: (v >> 16) & 0xff, g: (v >> 8) & 0xff, b: v & 0xff, a: 1 });

/** SwiftUI `Color.opacity(x)`: multiplies the alpha. */
export const opacity = (c: RGBA, x: number): RGBA => ({ ...c, a: c.a * x });

export function css(c: RGBA): string {
  const a = Math.max(0, Math.min(1, c.a));
  return `rgba(${c.r}, ${c.g}, ${c.b}, ${+a.toFixed(4)})`;
}

export interface Theme {
  backgroundTop: RGBA;
  backgroundBottom: RGBA;
  grid: RGBA;
  ink: RGBA;
  subtleInk: RGBA;
  labelFill: RGBA;
  palette: Record<MGColorRole, RGBA>;
}

export const board: Theme = {
  backgroundTop: hex(0x111a33),
  backgroundBottom: hex(0x0a0f1f),
  grid: { r: 255, g: 255, b: 255, a: 0.06 },
  ink: hex(0xeef2ff),
  subtleInk: hex(0x9aa4c7),
  labelFill: opacity(hex(0x0a0f1f), 0.82),
  palette: {
    force: hex(0xff5d73), normal: hex(0x4fc3f7), friction: hex(0xffb74d), gravity: hex(0xb388ff),
    tension: hex(0x64ffda), velocity: hex(0x69f0ae), accel: hex(0xffd54f), energy: hex(0xffd54f),
    kinetic: hex(0x69f0ae), potential: hex(0x4fc3f7), accent: hex(0x7c9cff), muted: hex(0x8a94b8),
    good: hex(0x69f0ae), warn: hex(0xffb74d), blue: hex(0x5b8cff), red: hex(0xff5d73), green: hex(0x4ade80),
    orange: hex(0xff9f43), purple: hex(0xb388ff), yellow: hex(0xffe066), teal: hex(0x2dd4bf), white: hex(0xeef2ff),
  },
};

export function color(theme: Theme, role: MGColorRole): RGBA {
  return theme.palette[role] ?? theme.ink;
}
