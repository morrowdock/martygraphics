# Cookbook

Ten short scenes you can copy. Each one teaches one idea of the [scene format](CONCEPTS.md). Each recipe is also a
file in [`docs/cookbook`](cookbook), so you can check it or load it directly.

**To try a recipe:** paste it into the `sceneJSON` string of the [quick start](../README.md#quick-start) program, or
save it as a file and check it with [`marty-scene-validate`](../tools/SceneValidator/README.md). In a SwiftUI app,
parse it with `MGParser.scene(data:)` and show it with `MartyGraphicsView(scene:)`.

**What "valid" means here.** The engine checks a recipe's shape, ranges, ids, references and text rules. It does not
check that the narration is true or that the numbers in it are right. The recipes were written so that their words
match their drawings, but that is the author's job, not the engine's.

| # | Recipe | Teaches | Kinds used |
| --- | --- | --- | --- |
| 1 | [A first board](#1-a-first-board) | The smallest useful scene | `body`, `text` |
| 2 | [Reveal a diagram step by step](#2-reveal-a-diagram-step-by-step) | `steps`, `show`, `focus` | `line`, `text` |
| 3 | [Move a highlight through a flow](#3-move-a-highlight-through-a-flow) | Step edits (`do`) | `node`, `edge`, `highlight` |
| 4 | [Plot supplied points](#4-plot-supplied-points) | Data plots and axis labels | `plot` |
| 5 | [Compare quantities with bars](#5-compare-quantities-with-bars) | Bar charts and units | `bars` |
| 6 | [Forces on a ramp](#6-forces-on-a-ramp) | Arrows attached to a body | `incline`, `body`, `vector` |
| 7 | [Timed motion](#7-timed-motion) | `move` animation | `line`, `body`, `text` |
| 8 | [Walk an array beside its code](#8-walk-an-array-beside-its-code) | Pointers, marks and code text | `array`, `text` |
| 9 | [A table of values](#9-a-table-of-values) | Tables, headers and marked cells | `table` |
| 10 | [A binary search tree from a template](#10-a-binary-search-tree-from-a-template) | Templates | `bst` |

## 1. A first board

One ball and one callout. The ball's `at` is its centre in world units; the default world is 12 × 8 with the origin at
the bottom left.

```json
{"v": 1, "title": "My first board",
 "items": [
  {"id": "dot", "k": "body", "at": [4, 4], "shape": "ball", "size": 1, "color": "teal"},
  {"id": "note", "k": "text", "at": [8, 4], "text": "A ball at x = 4, y = 4", "style": "callout"}
 ]}
```

File: [`01-first-board.scene.json`](cookbook/01-first-board.scene.json)

Try: change `"shape": "ball"` to `"box"`, or move the ball to `[40, 4]` to see a refusal (`body.at`: the point is off
the board).

## 2. Reveal a diagram step by step

Three steps build a right triangle with sides 6, 4.5 and 7.5. Each step's `show` list makes items appear at that step;
`focus` emphasises one of them.

```json
{"v": 1, "title": "Build a right triangle",
 "items": [
  {"id": "base", "k": "line", "from": [2, 2], "to": [8, 2], "color": "blue"},
  {"id": "height", "k": "line", "from": [8, 2], "to": [8, 6.5], "color": "orange"},
  {"id": "hyp", "k": "line", "from": [2, 2], "to": [8, 6.5], "style": "dashed", "color": "purple"},
  {"id": "la", "k": "text", "at": [5, 1.4], "text": "a = 6", "color": "blue"},
  {"id": "lb", "k": "text", "at": [9, 4.25], "text": "b = 4.5", "color": "orange"},
  {"id": "lc", "k": "text", "at": [4.3, 5], "text": "c = 7.5", "color": "purple"}
 ],
 "steps": [
  {"say": "Start with the base, a. It is 6 units long.", "show": ["base", "la"], "focus": "base"},
  {"say": "Add the height, b, at a right angle to the base. It is 4.5 units long.", "show": ["height", "lb"], "focus": "height"},
  {"say": "The longest side, c, is the hypotenuse. Check it: 6 squared plus 4.5 squared is 56.25, and 7.5 squared is 56.25.", "show": ["hyp", "lc"], "focus": "hyp"}
 ]}
```

File: [`02-reveal-in-steps.scene.json`](cookbook/02-reveal-in-steps.scene.json)

The side lengths are true for these coordinates, but the engine does not compute them: the labels and the
narration are typed text. If you move a point, update the words too.

## 3. Move a highlight through a flow

Three nodes, three directed edges and one highlight. Each `do` edit changes the highlight's `target`, so the glow moves
from step to step.

```json
{"v": 1, "title": "The water cycle",
 "items": [
  {"id": "sea", "k": "node", "at": [2.5, 3], "text": "Sea", "r": 0.8, "color": "blue"},
  {"id": "cloud", "k": "node", "at": [6, 6.3], "text": "Cloud", "r": 0.8, "color": "white"},
  {"id": "rain", "k": "node", "at": [9.5, 3], "text": "Rain", "r": 0.8, "color": "teal"},
  {"id": "up", "k": "edge", "a": "sea", "b": "cloud", "dir": true, "label": "evaporation", "color": "orange"},
  {"id": "down", "k": "edge", "a": "cloud", "b": "rain", "dir": true, "label": "precipitation", "color": "blue"},
  {"id": "back", "k": "edge", "a": "rain", "b": "sea", "dir": true, "label": "runoff", "color": "teal"},
  {"id": "now", "k": "highlight", "target": "sea", "color": "yellow"}
 ],
 "steps": [
  {"say": "The sun warms the sea, and some water evaporates.", "focus": "sea"},
  {"say": "The water vapour cools and forms clouds.", "focus": "cloud", "do": [{"id": "now", "key": "target", "value": "cloud"}]},
  {"say": "Water falls as rain and flows back to the sea.", "focus": "rain", "do": [{"id": "now", "key": "target", "value": "rain"}]}
 ]}
```

File: [`03-moving-highlight.scene.json`](cookbook/03-moving-highlight.scene.json)

Node text is at most 8 characters. An edge needs two existing `node` items (`edge.nodes` otherwise). This is a
diagram; nothing is simulated.

## 4. Plot supplied points

A `plot` draws the points you give it inside the ranges `xr` and `yr`. It does not compute a function.

```json
{"v": 1, "title": "Distance over time",
 "items": [
  {"id": "walk", "k": "plot", "at": [1.5, 1.4], "w": 9, "h": 5.4,
   "xr": [0, 4], "yr": [0, 7], "pts": [[0, 0], [1, 1.5], [2, 3], [3, 4.5], [4, 6]],
   "xl": "time (s)", "yl": "distance (m)", "color": "teal"}
 ],
 "steps": [
  {"say": "Five supplied points lie on a straight line: the walker covers 1.5 m in every second.", "focus": "walk"}
 ]}
```

File: [`04-plot-points.scene.json`](cookbook/04-plot-points.scene.json)

Try: add the point `[5, 7.5]`. The parser accepts it, but it lies outside `xr` and `yr`, so widen them to `[0, 5]`
and `[0, 8]` to keep it inside the axes.

## 5. Compare quantities with bars

Up to 6 bars, each with a label of up to 16 characters. `unit` is up to 8 characters. The counts here are invented.

```json
{"v": 1, "title": "Class pet poll",
 "items": [
  {"id": "poll", "k": "bars", "at": [1.5, 1.6], "w": 9, "h": 4.8, "unit": "votes",
   "bars": [
    {"label": "Fish", "value": 7, "color": "blue"},
    {"label": "Cat", "value": 12, "color": "purple"},
    {"label": "Dog", "value": 9, "color": "teal"}
   ]}
 ],
 "steps": [
  {"say": "Cat has the most votes in this invented poll: 12 of 28.", "focus": "poll"}
 ]}
```

File: [`05-compare-bars.scene.json`](cookbook/05-compare-bars.scene.json)

The bars are drawn from `value`. The narration is not: if you change a value, change the sentence as well.

## 6. Forces on a ramp

A block on a 30° ramp with three arrows. Each `vector` uses `on` to start at the block's centre. `angle` is in degrees
counter-clockwise from the positive x axis, so `-90` points down and `120` points away from this ramp's surface.

```json
{"v": 1, "title": "Forces on a block at rest",
 "items": [
  {"id": "ramp", "k": "incline", "at": [1.5, 1.5], "base": 8, "angle": 30, "color": "muted"},
  {"id": "block", "k": "body", "at": [5.25, 4.25], "size": 1, "angle": 30, "color": "blue"},
  {"id": "weight", "k": "vector", "on": "block", "angle": -90, "len": 2, "label": "weight", "color": "gravity"},
  {"id": "normal", "k": "vector", "on": "block", "angle": 120, "len": 1.73, "label": "normal force", "color": "normal"},
  {"id": "grip", "k": "vector", "on": "block", "angle": 30, "len": 1, "label": "friction", "color": "friction"}
 ],
 "steps": [
  {"say": "A block rests on a 30 degree ramp. Its weight points straight down.", "show": ["ramp", "block", "weight"], "focus": "weight"},
  {"say": "The ramp pushes back at a right angle to its surface: the normal force.", "show": ["normal"], "focus": "normal"},
  {"say": "Friction points up the slope and stops the block from sliding. The arrow lengths are typed by the author.", "show": ["grip"], "focus": "grip"}
 ]}
```

File: [`06-forces-on-a-ramp.scene.json`](cookbook/06-forces-on-a-ramp.scene.json)

The arrow lengths follow a block at rest (normal = weight × cos 30°, friction = weight × sin 30°), but they are typed
numbers. The engine does not compute or check forces in a 2D scene.

## 7. Timed motion

A body with `move` glides to the `to` point in `t` seconds (0.3 to 10) and back, with easing, for as long as the board
plays.

```json
{"v": 1, "title": "A cart moves along a track",
 "items": [
  {"id": "track", "k": "line", "from": [1, 2], "to": [11, 2], "style": "ground", "color": "muted"},
  {"id": "cart", "k": "body", "at": [2, 2.5], "size": 1, "color": "orange", "move": {"to": [10, 2.5], "t": 3}},
  {"id": "start", "k": "text", "at": [2, 1.2], "text": "start", "color": "blue"},
  {"id": "finish", "k": "text", "at": [10, 1.2], "text": "finish", "color": "purple"}
 ],
 "steps": [
  {"say": "The cart glides from start to finish in 3 seconds, then back again, over and over. This is a timed animation, not a physics simulation.", "focus": "cart"}
 ]}
```

File: [`07-timed-motion.scene.json`](cookbook/07-timed-motion.scene.json)

This is a timed animation. It does not model speed, mass or friction.

## 8. Walk an array beside its code

An array with one pointer and one marked cell. Step edits replace the pointer list (`ptrs`) and the marks
(`marked`). Text in the `code` style is drawn monospaced and left-aligned at its `at` point, so one text item per line
reads as a listing. Code text may contain `<` and `>`; other text may not.

```json
{"v": 1, "title": "Find the largest value",
 "items": [
  {"id": "vals", "k": "array", "at": [3.5, 4.5], "vals": [4, 9, 2, 7], "ptrs": [{"i": 0, "label": "i"}], "marked": [0], "color": "blue"},
  {"id": "c1", "k": "text", "at": [6.8, 6], "text": "best = vals[0]", "style": "code"},
  {"id": "c2", "k": "text", "at": [6.8, 5.4], "text": "for x in vals:", "style": "code"},
  {"id": "c3", "k": "text", "at": [6.8, 4.8], "text": "    if x > best:", "style": "code"},
  {"id": "c4", "k": "text", "at": [6.8, 4.2], "text": "        best = x", "style": "code"}
 ],
 "steps": [
  {"say": "Start at index 0. The largest value so far is 4.", "focus": "vals"},
  {"say": "Index 1 holds 9. It is larger, so 9 becomes the largest so far.", "do": [{"id": "vals", "key": "ptrs", "value": [{"i": 1, "label": "i"}]}, {"id": "vals", "key": "marked", "value": [1]}]},
  {"say": "Index 2 holds 2. The largest stays 9.", "do": [{"id": "vals", "key": "ptrs", "value": [{"i": 2, "label": "i"}]}]},
  {"say": "Index 3 holds 7. The largest stays 9, so the answer is 9.", "do": [{"id": "vals", "key": "ptrs", "value": [{"i": 3, "label": "i"}]}]}
 ]}
```

File: [`08-array-and-code.scene.json`](cookbook/08-array-and-code.scene.json)

Cells hold at most 6 characters; pointer labels at most 8. A pointer index must exist in the array (`array.ptr.i`).

## 9. A table of values

A table with a header row and one marked cell. `marked` uses `[row, column]`, counted from 0, with the header as row 0.

```json
{"v": 1, "title": "The 3 times table",
 "items": [
  {"id": "times", "k": "table", "at": [6, 4.2], "header": true,
   "cells": [["n", "3 × n"], [1, 3], [2, 6], [3, 9], [4, 12]],
   "marked": [[3, 1]], "label": "3 × n", "color": "teal"}
 ],
 "steps": [
  {"say": "Each step down the table adds 3 to the right column. The marked cell shows 3 × 3 = 9.", "focus": "times"}
 ]}
```

File: [`09-table-of-values.scene.json`](cookbook/09-table-of-values.scene.json)

Every row needs the same number of cells (`table.cells` otherwise). Cells are strings of up to 12 characters or
numbers.

## 10. A binary search tree from a template

A template builds the items and steps for you. `bst` inserts `values` in order and, with `find`, walks the search.

```json
{"v": 1, "title": "Search for 14", "template": "bst",
 "params": {"values": [10, 6, 15, 3, 8, 14, 20], "find": 14}}
```

File: [`10-search-tree-template.scene.json`](cookbook/10-search-tree-template.scene.json)

`values` holds 1 to 15 distinct integers from -999 to 999 (`template.check` if two are equal); a tree that is too
deep is refused with `template.build`. For a sorted-array pair search, use
`two_pointers`: see the [showcase scene](../Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json).

## More scenes to copy

- The seven [showcase scenes](../Examples/Showcase/Sources/MartyShowcase/Scenes), including the opt-in
  `shortest_path` graph template ([gallery](GALLERY.md#2d-scenes)).
- A [region, table and code listing](fixtures/v1/table-region-code.scene.json) and the
  [minimal scene](fixtures/v1/scene.json) from the protocol fixtures.

## How these recipes were checked

On 2026-11-26 each recipe file was checked with a draft Python preflight of the scene v1 rules (not part of this repository; `scene_v1_check.py`, SHA-256 `0d479ba05beb…`): **10 of 10 pass**.

| Recipe file | Preflight |
| --- | --- |
| `01-first-board.scene.json` | pass |
| `02-reveal-in-steps.scene.json` | pass |
| `03-moving-highlight.scene.json` | pass |
| `04-plot-points.scene.json` | pass |
| `05-compare-bars.scene.json` | pass |
| `06-forces-on-a-ramp.scene.json` | pass |
| `07-timed-motion.scene.json` | pass |
| `08-array-and-code.scene.json` | pass |
| `09-table-of-values.scene.json` | pass |
| `10-search-tree-template.scene.json` | pass (parameters only; the template expands in Swift) |

The preflight follows the parser's rules for shape, ranges, references, text and step edits. It cannot expand a
template, so for recipe 10 it checks the parameters only. The Swift parser is the authority: run
`marty-scene-validate -- docs/cookbook/*.scene.json` on a Mac for the final answer. That run has not been recorded
for these recipes yet.
