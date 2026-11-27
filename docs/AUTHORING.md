# Authoring scenes: conventions, checks and worked examples

This guide is for anyone who writes or reviews [v1 scene](PROTOCOL.md) JSON or [ML explainer](ML-EXPLAINER.md)
documents. The parser decides what is *valid*. This guide covers what makes a valid scene *mechanically correct*:
the right items, numbers that agree with each other, directions and positions that follow the engine's
conventions, and steps in the right order. It describes the **2D renderer** (`MGCanvasRenderer`); 3D scenes
(`"dim": "3d"`) are drawn by the 3D renderer and are not covered here. The conventions come from the Swift sources
(`MGParser`, `MGTimeline`, `MGLayout`, `MGCanvasRenderer`). Notes marked *renderer behaviour* describe how the
current 2D renderer draws; they are not part of the wire format.

## Checking a scene

1. Validate it: `marty-scene-validate --hints FILE` (scenes) or `marty-scene-validate --ml-kit --strict --hints FILE`
   (ML documents). A refusal names one reason token and a fix hint ([hint table](#repair-hints)).
2. Lint it: `python3 tools/scene_lint.py FILE` lists [common mistakes](#common-mistakes) the parser accepts, review
   cues to look at, and the inputs the lint did not check.
3. Optionally, review the finished scene with the [review checklist](#review-checklist).
4. Repair and check again. If the same reason repeats, re-read its row in the hint table.

## Review checklist

These checks are optional. They help when reviewing a finished scene against its request.

```text
1. Items:       every item the request names is present, with the right kind.
2. Values:      check computed values against the request: formula, value, units and how each is
                displayed (see "Text and numbers").
3. Directions:  check each vector's angle against its physical direction (0 right, 90 up, 180 left, 270 down).
4. Scale:       one world-units-per-unit factor per quantity type; each len = value × factor.
5. Layout:      each item's anchor (centre or lower-left, see the table) and its extent lie inside the world.
6. Steps:       each step's narration, reveals (show), focus and edits come in the intended order. Step 0
                edits apply before the first frame, so the starting state is seen only when step 0 is edit-free.
7. Not supported: anything approximated (pie chart, arc, curved motion) is said so in the narration.
8. Text:        no < > { }; lengths within limits; every number in text matches a computed value.
```

## Coordinates and drawing conventions

World units are square (one uniform scale, no distortion), x points right, y points up, the origin is the
bottom-left corner and the default world is 12 × 8 (`world` sets 2–100 per side). The board shows a dot grid
every `max(1, round(w / 24))` world units. Points may lie from −25 % to 125 % of each side, but anything outside
0…w × 0…h is off the board.

| Kind | Anchor and geometry | Notes |
| --- | --- | --- |
| `body` | `at` is the centre. A box has side `size`; a ball (`shape: "ball"`) has diameter `size` (default 1). `angle` rotates the box counter-clockwise about its centre, in degrees, so a rotated box reaches up to `size`/√2 from `at`. | *Renderer behaviour:* a label that fits is drawn inside, otherwise below. `move: {to, t}` glides in a straight line to `to` and back, forever: it is not physics. |
| `incline` | `at` is the bottom-left (acute) vertex. The base runs right by `base`; the vertical side is at the right end, height `base · tan(angle)`. The slope always rises to the right. | Slope direction = `angle`; outward normal = `angle + 90`; down-slope = `angle + 180`. |
| `vector` | `from: [x, y]` is the tail, or `on: "<body or node id>"` anchors it to that item's centre. `angle` is degrees counter-clockwise from +x; `len` is the drawn length in world units. | A vector `on` an item starts at the item's edge and runs `len` from there; a `from` vector starts exactly at its point (use `from` for head-to-tail diagrams). `len: 0` draws nothing. *Renderer behaviour:* arrows with the same angle on one body fan out sideways, and the label sits at the tip. The vector field `dir` (a 3D direction `[x, y, z]`) is 3D only; an edge's `dir` is a different, Boolean field. |
| `line` | `from` → `to`. `style`: `solid`, `dashed` or `ground`. | `ground` hatches the right-hand side of the direction of travel: below a left-to-right line, above a right-to-left one (draw a ceiling right to left). |
| `axes` | `at` is the origin; arrows run `w` along +x and `h` along +y only (an L shape). | For axes through a centre (four quadrants), draw two lines. |
| `plot` | `at` is the lower-left corner of a `w` × `h` frame; `xr` and `yr` are the data ranges; `pts` are **data** coordinates. A data point (x, y) is drawn at `at + (w·(x − x0)/(x1 − x0), h·(y − y0)/(y1 − y0))`. | One polyline per plot. *Renderer behaviour:* points outside the ranges are drawn up to 2 screen points past the frame, then clipped. Tick labels show only x0, x1, y0, y1. To overlay series, give several plots the same `at`, `w`, `h`, `xr`, `yr`. |
| `bars` | `at` is the lower-left corner of the `w` × `h` frame. | Heights are scaled to the largest \|value\| (so bars are proportional); a negative value is drawn as a positive height. Each value is printed above its bar with `unit`. |
| `array` | `at` is the centre of the row; each cell is `cell` wide (default min(1, span / 4)). | *Renderer behaviour:* index numbers are drawn above the cells, pointers below (several on one cell stack), `marked` cells are tinted, the label sits above. |
| `table` | `at` is the centre; `cw` × `rh` per cell. | Row 0 is tinted when `header` is true. `marked` holds `[row, column]` pairs counted from the first row (the header is row 0). *Renderer behaviour:* a table whose data cells (the rows after the header, or every row without `header`) are all empty is not drawn, so a header-only table appears once a data cell is filled. |
| `node` | `at` is the centre, `r` the radius (default min(0.5, span / 6)); `text` (≤ 8 characters) is drawn inside. | |
| `edge` | Joins nodes `a` and `b`; the Boolean `dir: true` draws an arrow from `a` to `b`. | *Renderer behaviour:* the label sits at the midpoint. |
| `text` | `at` is the centre (`label`, `title`, `callout`); `code` text starts at `at` and is left-aligned. | |
| `highlight` | A pulsing ring around `target`'s footprint. Move it with an edit of `target`. | |
| `orbit`, `pulley` | `at` is the centre, `r` the radius. An orbit is a dashed circle; it does not move anything. | |
| `spring`, `rope`, `path`, `region` | `spring` coils from `from` to `to`; `rope` (2–6 points) and `path` (2–64) are polylines; `region` (3–64) is a filled polygon, closed automatically. | |

## Steps, edits and timing

- The first frame is step 0 **with step 0's edits already applied**; the authored state is never shown on its
  own when step 0 edits it. To show a starting state, make step 0 edit-free.
- `show` reveals: an item first listed at step k is hidden before step k and visible from then on. Items never
  listed in any `show` are visible from step 0. `show` only reveals items; later edits can still stop an item
  from drawing (a vector edited to `len: 0`, a table whose data cells are all emptied).
- A vector, edge or highlight whose anchor is hidden is hidden too.
- `focus` draws a pulsing ring around one item (not around a highlight item).
- `do` holds 1–6 edits `{"id", "key", "value"}`. Edits accumulate across steps. The value replaces the whole field
  (a list too: send the full `vals`, `ptrs` or `bars`). `id` and `k` cannot change. Setting a vector's `on`
  removes `from`, and the reverse.
- Each edit re-validates its item at once, in order: when an array shrinks, edit `ptrs` and `marked` before
  `vals`; when it grows, edit `vals` first.
- Limits: 8 steps, 16 ids per `show`, 6 edits per step, narration 1–200 characters.

## Text and numbers

- Plain text refuses `<` and `>` (write ≤, ≥, →, "less than"), braces `{ }` (they are template placeholders),
  URLs, code fences and control characters. `code` text may contain comparisons such as `i < n`, but no tags.
- Lengths: title 60, label 40, text 120, narration 200, node text 8, array cell 6, pointer label 8, bar label 16,
  bars unit 8, table cell 12 (characters).
- Numbers in array cells, table cells and bar values are displayed with the engine format: no decimals from 100,
  one decimal from 10, two below 10, trailing zeros dropped. `0.375` shows as `0.38`, `36.75` as `36.8`. Use a text
  cell, or scale the value (12.5 %), when the exact digits matter, and quote the displayed digits in narration.
- A number in narration should match a computed value (review checklist line 2), rounded the same way
  everywhere it appears.

## Worked examples

Each example is valid; the text outside the JSON shows the arithmetic behind its numbers.

**Forces on an incline.** A 3 kg block slides down a 20° slope with kinetic friction μ = 0.2, g = 9.8:
W = 29.4 N (angle 270), N = 29.4 cos 20° = 27.6 N (angle 20 + 90 = 110), friction = 0.2 × 27.6 = 5.53 N up the
slope, against the motion (angle 20). Scale 0.08 world units per newton. The block sits on the slope:
centre = at + d·(cos 20°, sin 20°) + (size/2)·(−sin 20°, cos 20°), here with d = 5 and size 1.2.

```json
{"v":1,"items":[{"id":"slope","k":"incline","at":[1,1],"base":9,"angle":20},
{"id":"block","k":"body","at":[5.49,3.27],"size":1.2,"angle":20},
{"id":"W","k":"vector","on":"block","angle":270,"len":2.35,"label":"W = 29.4 N","color":"gravity"},
{"id":"N","k":"vector","on":"block","angle":110,"len":2.21,"label":"N = 27.6 N","color":"normal"},
{"id":"f","k":"vector","on":"block","angle":20,"len":0.44,"label":"f = 5.53 N","color":"friction"}],
"steps":[{"say":"Weight: 29.4 N straight down.","show":["slope","block","W"],"focus":"W"},
{"say":"Normal force: 27.6 N, perpendicular to the slope.","show":["N"],"focus":"N"},
{"say":"Kinetic friction: 5.53 N up the slope, against the sliding.","show":["f"],"focus":"f"}]}
```

**A function and a marked point.** y = 2^x on [0, 3]: `pts` are data coordinates. The point (2, 4) is drawn at
(1.5 + 8·2/3, 1.2 + 5.6·4/8) = (6.83, 4.0).

```json
{"v":1,"items":[{"id":"f","k":"plot","at":[1.5,1.2],"w":8,"h":5.6,"xr":[0,3],"yr":[0,8],
"pts":[[0,1],[0.5,1.41],[1,2],[1.5,2.83],[2,4],[2.5,5.66],[3,8]],"xl":"x","yl":"y"},
{"id":"mark","k":"body","at":[6.83,4],"shape":"ball","size":0.25,"color":"red"}],
"steps":[{"say":"At x = 2 the curve is at 4.","focus":"mark"}]}
```

**An algorithm walkthrough.** Finding the minimum: step 0 shows the input without edits; each later step edits
whole fields.

```json
{"v":1,"items":[{"id":"a","k":"array","at":[6,4],"vals":[7,3,9,2],"cell":1.2,"ptrs":[{"i":0,"label":"min"}]}],
"steps":[{"say":"Start: the minimum so far is 7.","focus":"a"},
{"say":"3 is smaller: min moves to index 1.","do":[{"id":"a","key":"ptrs","value":[{"i":1,"label":"min"}]}]},
{"say":"9 is not smaller; 2 is: min moves to index 3.","do":[{"id":"a","key":"ptrs","value":[{"i":3,"label":"min"}]}]}]}
```

**A structure that changes.** Removing the middle node of 1 → 2 → 3: re-point an arrow with an edit of `b`, and
mute the removed node (`show` only reveals items, so it cannot hide the node).

```json
{"v":1,"items":[{"id":"n1","k":"node","at":[2,5],"text":"1"},{"id":"n2","k":"node","at":[5,5],"text":"2"},
{"id":"n3","k":"node","at":[8,5],"text":"3"},{"id":"e12","k":"edge","a":"n1","b":"n2","dir":true},
{"id":"e23","k":"edge","a":"n2","b":"n3","dir":true}],
"steps":[{"say":"The list is 1 → 2 → 3.","focus":"n2"},
{"say":"Point 1 past 2, straight at 3.","do":[{"id":"e12","key":"b","value":"n3"},{"id":"n2","key":"color","value":"muted"}]}]}
```

**No pie kind.** A pie is drawn with one `region` per slice: the centre plus arc points every 10–15° (a 90° slice
from 0° to 90° uses the centre and about 7 arc points). If you use bars instead, say so in the narration ("shown as
bars, since the board has no pie chart").

**Templates.** `bst`: `values` are 1–15 distinct integers (−999…999) inserted in order; `find` (optional) is
searched after the build. `two_pointers`: `vals` are 2–12 integers sorted ascending; `target` is the pair sum.
A template scene has no `world`; it may add up to 10 `items`, `hide` template items and override them with
`over`. The template writes its own steps.

**ML kit.** Greedy generation picks the strictly highest logit (ties go to the earlier candidate), so give each
intended token the top logit of its step. `chosen` must keep a positive probability after every enabled stage:
with `topK`, it must be among the k highest logits; with `topP`, compute the softmax and keep the smallest prefix
that reaches p. A temperature sweep (`temperatures`) excludes `temperature`, `topK` and `topP`. An agent loop
needs a budget of at least 4 steps (5 with `review`) to reach `stop`. In a vision pipeline the patch edge must
divide both image sides.

## Common mistakes

| Mistake | Guard |
| --- | --- |
| Step 0 edits a field, so the starting state is never shown. | lint review cue `step0.edits` |
| `<` or `>` in a label or narration; braces in plain text. | refusal `*.text`, `step.say`, `item.label` with hint |
| A vector angle measured from vertical, or clockwise. | review checklist line 3 |
| A normal force drawn vertical on a slope; friction not along the slope. | review checklist line 3, incline row above |
| Plot points written in world units, or outside `xr` / `yr`. | lint `plot.outside` |
| A marker placed by guessing instead of the plot mapping formula. | review checklist line 5 |
| A displayed number rounds away from the narrated value (0.375 → 0.38). | lint `display.rounding` |
| Shrinking an array before moving its pointers or marks. | refusal `array.ptr.i`, `array.marked` with hint |
| A ceiling drawn left to right with `ground` style (hatching faces down). | lint review cue `line.ground.side` |
| An item outside the world, also after a later edit or a rotation. | lint `layout.outside` (text width is not measured) |
| `focus` on a highlight item (no ring is drawn). | lint `focus.highlight` |
| Negative bar values (drawn as positive heights). | lint `bars.negative` |
| An unsupported feature replaced silently. | review checklist line 7 |
| Unsorted `two_pointers` values or repeated `bst` values. | refusal `template.check` with hint |

## Repair hints

`marty-scene-validate --hints` and `--ml-kit --strict --hints` add one fix hint to each refusal. The same table is
public as `MGRepairHint.text(for:)` (scenes) and `MGMLReason.hint` (ML documents), and is mirrored in Python by
the [dev authoring eval](../evals/dev-authoring/tools/hints.py). The reason token stays the authority; a hint is a
suggestion, and an unknown reason has no hint.
