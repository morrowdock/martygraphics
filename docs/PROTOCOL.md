# Scene protocol v1

New to scenes? Read [Concepts](CONCEPTS.md) first, and copy a scene from the [cookbook](COOKBOOK.md).
This page is the full reference.

**Protocol version: 1. Package release: early preview (tag `v0.1.0`).** This guide was
first written against public baseline `55c98121766c8a079006ee3106289ee97c30e7cd`. Tables, regions, code
text, record-list parameters and the graph pack were added after it and are in `v0.1.0`; the experimental
`layer2d` section at the end is on `main` only. A wire `v: 1`
is not a package release tag or an API stability guarantee. Follow the
[release/install gates](DISTRIBUTION.md) before claiming a versioned remote install.

This is a serialization contract, not a model prompt. `MGParser` and `MGPatch`
are the authoritative validators. `MGGrammar.document()` exposes allowed/required
item keys, colors, limits, and the template registry directly from their tables;
it is a structural grammar inventory, not a complete JSON Schema validator.

A transport may wrap scenes as `{"type":"scene","scene":{...}}` and patches
as `{"type":"scenePatch","patch":{...}}`. Pass the inner object to the engine.

```json
{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}
```

[Copy the scene JSON](fixtures/v1/scene.json). The minimal scene and title patch
come from the already-public `MGGrammar` protocol examples; all fixtures are
synthetic, Apache-2.0, and contain no transport/provider configuration.

A scene requires `v: 1` and either a registered `template` with `params`, or an
`items` array. Optional fields include `title`, `alt` (a text alternative for the
whole board), `dim` (`2d` / `3d`), `world`, `camera`, `steps` and `sliders`
(learner sliders for `func` parameters). Template scenes also support `hide` and `over`.
World coordinates point right/up, with the origin at bottom-left; 3D adds z
toward the viewer. The default world is 12 by 8.

Kinds: body, incline, line, vector, axes, plot, spring, pulley, rope, orbit,
text, highlight, bars, path, array, node, edge, table, region, func, field. The
model types expose their geometry. In 3D the supported subset is body, incline,
line, vector, axes, orbit, text, highlight, path. Text styles are `label`
(default), `callout`, `title` and `code`. See [tables, regions and code text](#tables-regions-and-code-text),
[function graphs, vector fields and text alternatives](#function-graphs-vector-fields-and-text-alternatives)
and [learner sliders](#learner-sliders) for the newest additions.

Drawing conventions of the 2D renderer that the keys alone do not show: a vector `angle` is degrees
counter-clockwise from +x (0 right, 90 up); an incline's `at` is its bottom-left vertex and the slope rises to
the right; `plot`, `axes` and `bars` anchor at their lower-left corner, `array` and `table` at their centre;
plot `pts` are data coordinates, mapped through `xr` and `yr`. In steps, an item first listed in a `show`
appears at that step, and the first frame already applies step 0's edits. The [authoring guide](AUTHORING.md)
lists the 2D conventions, an optional review checklist and worked examples.

The engine rejects unknown keys, broken references, invalid parameter ranges,
invalid text, duplicate identifiers, and unsupported kinds. Limits include
8 KiB canonical scene JSON, 4 KiB patches, 24 full-scene items, 10 template
extras, 40 resolved items, and 8 wire-authored steps (up to 48 template-built steps). Limits apply to canonical JSON; the
input decoder allows up to twice the scene byte limit before canonicalization.

```json
{"v":1,"rev":0,"ops":[{"op":"title","title":"Synthetic dot"}]}
```

[Copy the patch JSON](fixtures/v1/title.patch.json). For a freshly parsed scene,
this changes the title and advances revision 0 to 1. Applying it a second time
fails with `patch.stale`. A controller stamps revisions; always read its current
`scene.revision` instead of assuming it is zero.

Patch operations: params, add, remove, set, steps, step, camera, title, dim.
A patch revalidates the entire resulting scene. Supply the current `rev` and
use `requireRevision: true` when applying updates from untrusted transports;
stale revisions are rejected. A direct engine caller can omit the revision
when performing a trusted local edit. Failed patches preserve the old value.

`MGStreamParser` offers provisional previews while receiving scene JSON;
`finish()` performs strict final validation. `MGSceneController` restores the
previous scene if final validation fails.

Packs use `MGPack`, `MGTemplate`, `MGTemplateBuild`, `MGFixtures.Demo` and,
optionally, `MGFixtures.PatchDemo` follow-up patches and fail-safe cases.
`MGPacks.validate` reports invalid identifiers, duplicate names, missing template
fixtures, invalid fixture scenes, broken example references, patches that do not
apply to their fixture (`patchInvalid`) and fail-safe cases that parse
(`invalidAccepted`). `register` is
atomic and serializes concurrent registrations. Every template-built item,
world, title, step, and camera is revalidated with the wire rules. Optional
`MGFewShot` records are reference metadata; the built-in public pack provides
no model instructions or generation examples.

Highlight chains must terminate at a non-highlight item. Cycles, self-targets,
and missing targets are rejected, including after each cumulative step edit.
Layout also resolves chains iteratively with a visited set to protect callers
that construct items directly without parsing.

The built-in templates are `bst` and `two_pointers`. Mechanics drawing
primitives and standard math helpers remain available; mechanics walkthrough
templates are not included.

## Tables, regions and code text

These are additive changes, included in `v0.1.0`. Wire `v: 1`
is unchanged and every scene that parsed before parses to the same result. All
three are 2D only: in a 3D scene `table` and `region` fail with
`3d.kind.table` / `3d.kind.region`, and `code` text fails with `3d.text.code`
(also when a `dim` patch or a step edit would bring it into 3D). Plain 3D text
is unchanged.

```json
{"id":"grid","k":"table","at":[8.5,5.5],"cells":[["key","value"],["a",1]],"header":true,"marked":[[1,1]]}
```

- `table`: required `at` (centre) and `cells`, 1–8 rows (`MGLimits.tableRows`)
  of 1–6 cells (`tableCols`), every row the same length. A cell is a string of
  at most 12 characters (`tableCellText`) with the plain-text rules, an empty
  string, or a number below 10⁶ in magnitude whose displayed text also fits 12
  characters. Optional `header` (bool: the first row is tinted), `cw` cell width
  0.3 to world span / 3 (default 1.6, capped to that range), `rh` row height 0.3 to
  span / 6 (default 0.7, capped), `marked` (a list of `[row, column]` integer
  pairs, at most rows × columns entries), `label`, `color` (default `accent`). Reasons:
  `table.cells` (shape or count), `table.cell` (a cell value), `table.marked`,
  `table.cw`, `table.rh`, `table.header`. Rows draw on in order.
- `region`: required `pts`, 3–64 points (`MGLimits.points`), drawn as a filled,
  closed polygon. Optional `dashed`, `label`, `color` (default `accent`).
  Reason: `region.pts`.
- Text style `code`: drawn monospaced and left-aligned at `at`, so stacked lines
  read as a listing. Leading spaces are kept (only surrounding newlines are
  trimmed) and `<` / `>` are allowed unless the text looks like a markup tag
  (`<` followed by a letter, `/`, `!` or `?` with a later `>`). Code fences,
  URLs, control characters and whitespace-only text are refused (`text.text`).
  Braces are still placeholders, as in all text. Other styles keep the strict
  rule: no `<` or `>` at all.

[Copy the scene JSON](fixtures/v1/table-region-code.scene.json); it equals the
built-in `cells` fixture.

## Function graphs, vector fields and text alternatives

Additive, unreleased changes to the unversioned preview, **pending Mac
verification** (written and checked offline; the Swift tests have not run yet).
Wire `v: 1` is unchanged and every scene that parsed before parses to the same
result. `func` and `field` are 2D only (`3d.kind.func`, `3d.kind.field`, also
through a `dim` patch or a step edit); `alt` works in 2D and 3D.

```json
{"id":"wave","k":"func","at":[0.6,1.2],"w":5.4,"h":4.2,"xr":[-3.2,3.2],"yr":[-1.6,1.6],"y":"a*sin(x)","a":1,"shade":[0,3.14],"mark":1.5708,"label":"y = a sin x"}
```

- `func`: a graph of y = f(x) that the **engine** samples. The model writes the
  expression, never the points, so no plotted value can be a model's arithmetic
  slip. Required `at` (frame bottom-left), `w`, `h` (0.5 to 1.25 × world span,
  as `plot`), `xr`, `yr` (increasing, within ±10⁶, at least 10⁻⁶ wide) and `y`
  (an expression in `x`). Optional `a`, `b`, `c` (parameters within ±1,000; an
  expression may read only the ones that are set), `period` (0.5–20 s: the graph
  moves, and `y` must read `t`, seconds 0…period, repeating), `shade` (`[x0, x1]`
  inside `xr`: fill between the curve and y = 0), `mark` (an x inside `xr`: the
  engine draws the point and writes its coordinates, for example `(1.57, 1)`),
  `xl`, `yl`, `label`, `color` (default `accent`).
- Sampling: 257 values on 256 equal intervals from `xr[0]` to exactly `xr[1]`.
  Where the function has no value (`sqrt(-1)`, `ln(0)`, `1/0`) the curve has a
  gap; the piece before ends 1/1024 of an interval before it and the next starts
  1/1024 after it, so `sin(x)/x` shows a hole one probe wide and `ln(x)` runs up
  to its asymptote. The midpoint of every interval between two values is
  evaluated too; where the function has no value there (`1/x` or `x/x` when 0
  falls exactly between two samples) the piece splits there the same way, so no
  line and no shade crosses the gap, at parse time and in every frame of a
  moving graph. Two neighbouring values outside the y range on opposite sides
  are bisected 8 times: a value inside the range means the curve crosses the view
  (it is joined); otherwise it is a pole and the curve breaks there, so `tan(x)`
  is never drawn with vertical lines through its asymptotes.
- Faithfulness checks, refused rather than drawn wrong: at every interval midpoint
  the drawn chord must be within 1 % of the frame height of the function
  (`MGLimits.funcTolerance`; the smaller of the vertical gap, both clipped to the
  y range, and the distance from the true point to the chord, so a steep curve
  such as `sqrt(x)` near 0 passes while aliasing such as `sin(80*x)` and a peak
  between samples are refused, `func.detail`); at most 16 breaks (`func.breaks`);
  something inside the y range (`func.empty`); the shaded interval inside one
  unbroken piece (`func.shade`); the marked point has a value inside the y range
  (`func.mark`). A moving graph is checked at t = 0, ¼, ½ and ¾ of its period,
  and at t = period it must match t = 0 to the same tolerance with the same gaps
  (`func.loop`), so every loop is seamless. Between the checked instants the
  marked point is drawn, with its coordinates, only while the function has a
  value there inside the y range. Expressions are refused as
  `func.y` (not text, empty, over 80 Unicode scalars, a character outside the
  grammar), `func.y.syntax`, `.tokens` (over 48), `.depth` (over 8 nested
  parentheses), `.name`, `.arity` and `.var.<v>` (`t` without `period`, a
  parameter that is not set, `y` in a `func`). A `period` whose expression does
  not read `t` is `func.period`. Other keys use `func.<key>`.

```json
{"id":"flow","k":"field","at":[6.6,1.2],"w":4.8,"h":4.2,"xr":[-2,2],"yr":[-2,2],"dx":"-y","dy":"x","n":[8,7],"style":"arrows"}
```

- `field`: one engine-evaluated arrow (`dx`, `dy`, expressions in `x`, `y` and
  the set parameters; no `t`) at the centre of each cell of an `n` = `[columns,
  rows]` grid (2–16 × 2–12; default 12 along the longer side of the frame and the
  other side in proportion, at least 3). Same frame keys as `func`. `style`:
  `arrows` (default; length in proportion to the vector in the plot's own
  coordinates, the longest 0.85 of a cell, and the largest magnitude written
  under the frame, `|v| up to 2.45` here), `unit` (equal arrows; opacity in four steps
  of the magnitude) or `slope` (equal segments without heads: a direction field
  for dy/dx = f(x, y) with `"dx":"1","dy":"f"`). A zero vector is a dot; a cell
  without a value stays empty. Reasons: `field.n`, `field.style`, `field.dx…` /
  `field.dy…` (the expression reasons above) and `field.empty` (no cell with a
  nonzero value).
- At most 6 graph checks per resolved scene (`items.expr`): each `func` and
  `field` item counts once, and each step or `over` edit that names one counts
  once more, because an edit checks the whole item again. So one graph can take
  up to five step edits. All are counted before any item is evaluated. The parse
  cost is bounded by construction (see `MGLimits.exprItems`: at most 7,169
  evaluations of at most 48 operations per checked instant, and at most 175,140
  per parse); typical graphs need about 513. Measurements on a Mac are pending.
- Step edits and `set` patches change these items like any other (for example
  `{"id":"wave","key":"a","value":1.5}`); the item is re-sampled and re-checked,
  and a refused value refuses the whole scene. Two graphs with the same number of
  samples blend point by point, so a step change morphs the curve.
  `MartyGraphicsView` keeps the items of the shown step for each scene revision
  and step, so drawing a frame does not apply the edits again.

The expression grammar is closed and evaluated by a small stack machine, never by
the host: no `NSExpression` (whose `FUNCTION` form can invoke arbitrary methods),
no JavaScriptCore, key paths, selectors or format strings.

```text
expr    := term (("+" | "-") term)*       term  := unary (("*" | "/") unary)*
unary   := ("+" | "-") unary | power      power := primary ("^" unary)?
primary := number | name | name "(" expr ("," expr)* ")" | "(" expr ")"
```

`^` is right-associative and binds tighter than a leading minus (`-x^2` is
-(x²)). Numbers are decimal without an exponent (`2`, `0.5`, `.5`, at most 12
characters). Names: `pi`, `e`, the variables `x y t a b c` and the functions
`sin cos tan asin acos atan sinh cosh tanh exp ln log sqrt abs` (`ln` is natural,
`log` base 10) and `min max` (two arguments). Multiplication is always written
(`2x` and `x(x+1)` are refused). Values follow IEEE 754.
`MGGrammar.document()` lists the vocabulary under `expression`.

Text alternatives:

- `alt` on the scene and on a step: plain text, at most 200 Unicode scalars, the
  rules and placeholders of `say` (reasons `alt`, `step.alt`, `template.alt`).
  It describes what the board shows for a reader who cannot see it.
  `MartyGraphicsView` reads it to VoiceOver after the step's narration; a step
  without `alt` uses the scene's. Without any `alt` the VoiceOver value is the
  narration alone, as before. Change a step's `alt` with the `steps` patch and the
  scene's with a new scene; there is no new patch operation.
- `MGDescribe.board(scene, step:hiding:)` is an engine-written fallback: one
  sentence naming each visible item's kind, label and engine-held numbers, for
  example "A graph of y = a*sin(x) labelled “y = a sin x” for x from -3.2 to 3.2
  and y from -1.6 to 1.6 with a = 1, shaded from x = 0 to 3.14, marking the point
  (1.57, 1); a vector field …". It describes structure, not meaning, and never
  describes concealed items. `MartyGraphicsView.describesBoard()` opts in to
  reading it when no `alt` is authored.

[Copy the graphs scene](fixtures/v1/graphs.scene.json) (it equals the built-in
`graphs` fixture) and [the moving wave](fixtures/v1/wave.scene.json) (`wave`).
The [expression cases](fixtures/v1/expressions.cases.json) and the
[graph cases](fixtures/v1/graphs.cases.json) hold the golden values, samples and
reasons; XCTest checks them against the parser and
[`tools/mg_expr.py`](../tools/mg_expr.py), an offline mirror for preflight tools,
checks them in the hosted `hygiene` job.

Not checked: what an expression or an `alt` text means, whether a graph is the
one a lesson needs, and accessibility on a device (VoiceOver has not been run).

## Audio graphs

Additive and unreleased, **pending Mac verification**: written offline; the
Swift build and tests have not run, and VoiceOver has not been run on a device.
There is no wire change: scene v1, every limit and every refusal reason stay as
they are.

While a `plot`, `func` or `bars` item is visible, `MartyGraphicsView` gives the
board an audio graph through Apple's `AXChartDescriptor`
(`accessibilityChartDescriptor`). VoiceOver offers it on the board (the Audio
Graph rotor item). Play turns a series into a tone that rises and falls with the
value. Chart details read the title, the summary, the axes and each series, and
the learner can step from point to point and hear each x and y. A board without
such an item gets no chart descriptor and reads exactly as before. A 3D board
never gets one.

`MGAudioGraph.chart(scene, step:hiding:)` builds the data. It is Foundation only,
so tests check it without VoiceOver:

| | `plot` | `func` | `bars` |
| --- | --- | --- | --- |
| x axis | `xl` (else "x"), `xr`, grid lines at the frame's quarters | as `plot` | the bar labels in order, titled "Bar" |
| y axis | `yl` (else "y"), `yr`, grid lines at the quarters | as `plot` | "Value", or "Value (J)" with a `unit`; from the smaller of 0 and the lowest value to the larger of 0 and the highest (0 to 1 when every value is 0); values read with the unit |
| Series | the points as written, as one line | one line per piece the board draws (two samples or more), from the engine's samples (the ones it drew and checked), named "…, piece 2 of 3" when there are several; the marked point, where the board shows its dot, is added inside its piece as "marked point" with the engine's value (the printed one) | the values in order, not a line |

- Every number is one the engine holds: the `func` samples are never
  recomputed, and values read as the board writes them (`MGPhysics.format`).
- Series name: the item's `label`, else `y = …` for a `func`, else "plot" or
  "bars" (numbered when names repeat), then ", piece 2 of 3" for a `func` drawn
  in several pieces. Chart title: the first label, else the scene title, else
  "Graph" or "Bar chart".
- What is charted is what the board draws: `MGAudioGraph` and
  `MGCanvasRenderer` share the checks (`MGGraph.frame`, `MGGraph.plotTrace`,
  `MGGraph.barsOrigin`, `MGGraph.mark`). A `bars` item needs its `at` and a bar;
  a `plot` is charted only when the board draws its line (every point finite,
  finite and increasing ranges); a `func` needs a finite frame; the marked point
  is charted only where the board shows its dot (its value and the drawn curve
  inside the y range). Only items built in code, never parsed ones, fail these.
- Summary: the `MGDescribe.item` text of the charted items (the text of
  `describesBoard()`), then one sentence counting the charts left out.
- One chart per board: the first visible chart item in item order, with every
  later `plot` or `func` drawn in the same frame (same `at`, `w`, `h`, `xr` and
  `yr`) as more series. Another frame or another bar chart is left out and
  counted in the summary.
- The chart follows the current step (its edits and `show`) and the learner's
  slider values (`MGAudioGraph.chart(scene, items:hiding:)` with the items the
  board draws, see "Learner sliders"), and leaves out concealed items, as
  `MGDescribe` does.
- Motion and Reduce Motion: the chart is the motion's first frame (t = 0), so the
  samples of a moving `func` as parsed and spring energy bars at their first
  values. The board shows that frame when Reduce Motion is on. The chart never
  moves and does not depend on Reduce Motion or playback.
- At most 290 points per item over all its series (`MGAudioGraph.maxPoints`):
  257 grid values + 32 (two for each of at most 16 breaks) = 289 samples of a
  checked `func` (`maxSamples`), and 1 marked point. A gap at an interval
  midpoint adds its two probes, a gap at a grid value replaces that value with at
  most two probes, and a pole adds none. A `plot` holds at most 64 points and
  `bars` at most 6, so no parsed scene is cut. An item built in code with more
  points keeps 290 of them, evenly spaced over all its pieces with its first and
  last, and the summary says "plays 290 of its N points". Bars whose value is not
  finite are left out.

Not checked: how VoiceOver plays and reads these charts on a device (needs a
physical device; no device test has run) and whether the summary is enough for a
given lesson.

## Learner sliders

Additive and opt-in, unreleased, **pending Mac verification**. It was written on
a machine without the Apple toolchain. The Foundation-level engine code
type-checked, and `SliderTests` passed, with a Linux Swift build in which
Darwin-only calls were stubbed; the Python mirror passed too. The SwiftUI view,
the Apple-platform build and VoiceOver have not run. A scene without `sliders`
parses and draws exactly as before.

```json
"sliders":[{"param":"a","min":0,"max":2,"step":0.25,"default":1,"label":"Height a"}]
```

- `sliders` (scene key): 1 to 3 sliders. Each has exactly `param` (`a`, `b` or
  `c`), `min` and `max` (within ±1,000, the `func` parameter bound, `min` below
  `max`), `step` (above 0; it divides `max − min` into a whole number of steps,
  at most 100, and every stop has a value and a label of its own, else
  `slider.grid`), `default` (exactly the value of one stop, else
  `slider.default`: `0.30000000000000004` is not the stop `0.3`, and `1e-12` is
  not the stop `0`) and `label` (1–40 characters of plain text, without
  placeholders: the board shows the value beside it). One slider per parameter.
- The engine gets exactly the shown value. At every stop, both ends and the
  default included, the number sent to the engine is exactly the number the
  stop's label reads as (`MGSlider.value(at:)`). A grid where that cannot hold
  is refused as `slider.grid`: an end whose label does not read back as exactly
  that end (`min` 0, `max` 1.0000000002, `step` 1 would show the last stop as
  `1`), or a stop whose label does not read back as exactly its value or whose
  value falls outside `min…max`. The default never replaces a stop's value.
- A slider drives every `func` that sets its parameter, so the board has one
  value of `a`, as in a graphing calculator. At least one `func` must set it
  (`slider.unbound`), and each must set it to the slider's `default`
  (`slider.default.<id>`), so a host that shows no sliders draws the board at
  the default. Sliders drive `func` items only: a `field` that sets the same
  parameter is refused (`slider.field`), and so is a step edit of it
  (`slider.edit`); the slider is the one source of the value. At most 6 pairs
  of a slider and a `func` it drives (`sliders.bindings`).
- Both ends of each range are checked at parse time with every other parameter
  at its default, through the same item rules as a parse: a driven `func` that
  refuses an end gives `slider.<param>.min.<reason>` or
  `slider.<param>.max.<reason>`, for example `slider.b.max.func.detail` when
  `sin(b*x)` aliases at the largest `b`. That adds at most 12 item checks to a
  parse (`MGLimits.sliderBindings`).
- Moving a slider re-parses each driven `func` with `MGParser.item`, the path of
  a parse and a step edit (`MGSliderState`), so samples, pieces, the shaded band,
  the marked point and every readout number come from the engine, never from the
  model. A position whose graph fails a check (an interior value such as `a = 0`
  in `x/a`, `func.empty`) is not shown: the board keeps the last accepted value
  and says why ("a = 0 is not shown: nothing of the graph would be in view.").
  A step whose own edits refuse the current values sends every slider back to its
  default. Patches re-validate sliders with the rest of the scene; a patch cannot
  change them (a `set` of a driven parameter is refused with
  `slider.default.<id>`). While a scene streams, its sliders join the preview
  once the graphs they drive have arrived, as steps do; the final parse is strict.
- `MartyGraphicsView` shows the sliders under the board when it shows its
  controls and is not read-only; a row is shown while a graph it drives is on the
  board and not concealed. Each is a native slider with the label as its
  VoiceOver label, the value as its value, the range and step as its hint, and an
  adjustable action that moves one step per swipe, past any position the engine
  refuses; a refused position is announced. One form writes each number (the
  shown and spoken value, the hint, the readout and the refusal note,
  `MGSlider.text`): the fewest places, up to 6, that write `min` and `step`
  exactly, trailing zeros removed, while that names the value (read back, it is
  within a millionth of a step of it, so neighbouring stops never share a label,
  and a nonzero value never reads as `0`); otherwise the fewest significant
  digits that do (`0.0000001`, `1.0000001`; below 10⁻⁹ as `1.5e-12`). Readouts under the sliders are
  engine numbers (`y = a sin(bx) + c: a = 1.5, b = 2, c = 0.5, marked point (1.57,
  0.5)`). The text uses Dynamic Type styles, and at accessibility sizes the label
  and value stack. After a slider moves, the board's VoiceOver value reads the
  engine's description of what is drawn instead of the authored `alt`, which
  describes the default. The board's audio graph ("Audio graphs") is built from
  the same items, so it plays the graph at the slider values, not the authored
  default. Lessons and explainer boards drop a scene's sliders, as
  they drop its steps: their own controls drive them.
- `MGGrammar.document()` lists the key under `sceneKeys` and the slider shape
  under `sliders`. Refusal reasons have one-line fixes in `MGRepairHint`.

[Copy the slider scene](fixtures/v1/sliders.scene.json). The
[slider cases](fixtures/v1/sliders.cases.json) hold accepted scenes and the
reason of each refused one; XCTest (`SliderTests`) and the Python tools
(`tools/mg_expr.py`, `tools/scene_v1_check.py`) check the same file.

Not checked: whether a range teaches anything, interior values at parse time
(only the ends and the default are checked; other positions are checked when the
learner reaches them), and VoiceOver, Dynamic Type and the adjustable action on a
device.
## Readouts: slopes and areas

Additive, unreleased, **pending Mac verification** (written and checked offline:
the Python mirror ran, and so did a Linux build of the Foundation-only engine
with its XCTests; the Mac run has not). A `func` item may ask the engine for
calculus numbers, and any text of the scene names them as placeholders, so the
model never writes these numbers itself.

```json
{"id":"wave","k":"func","at":[1,1.2],"w":10,"h":5,"xr":[-3.2,3.2],"yr":[-1.6,1.6],"y":"sin(x)","shade":[0,3.14159],"mark":1,"readouts":["value","slope","area"],"label":"slope {wave.slope}"}
```

- `readouts`: 1 to 3 distinct names (`func.readouts`). `value` is f(m) at the
  marked x (`mark`), `slope` the derivative f′(m) there (the slope of the
  tangent), and `area` the signed area ∫ f(x) dx over the shaded interval
  (`shade`; parts below y = 0 count as negative). `value` and `slope` need a
  `mark` (`func.readouts.mark`) and `area` a `shade` (`func.readouts.shade`). A
  moving graph (`period`) has no readouts (`func.readouts.period`): its numbers
  would change while the text stays. These are checked before anything is
  sampled; the drawing checks (`func.detail`, `func.shade`, `func.mark`, …) run
  next, then the readouts in the order `value`, `slope`, `area`.
- Placeholders: `{<id>.<readout>}`, for example `{wave.slope}`, in the title,
  `alt`, step `say` and `alt`, text items, labels (the graph's own too), and lesson
  and explainer lines. Each `func` item that lists readouts is checked first,
  without its texts, so a text may come before the graph in `items`. The number
  is written as the engine writes every number (`MGPhysics.format`: two decimals
  below 10, one below 100, whole numbers from 100, no trailing zeros), so
  `{wave.slope}` above is `0.54` and `{wave.area}` is `2`. The values are also in
  `MGScene.values` under the same names, without a unit. A readout that the item
  does not list, or of an item that does not exist, is
  `<text reason>.placeholder.readout` (for example `text.text.placeholder.readout`);
  any other dotted name keeps its old reason (`text.text.placeholder`; in an
  explainer it is a 3D fact, as before).
- `slope` is proven, never estimated. Forward-mode differentiation applies the
  closed-form rule of each operation of the expression (d sin u = cos u du,
  d uᵛ = v uᵛ⁻¹ du when the exponent v does not read x, d uᵛ = uᵛ (v′ ln u +
  v u′ / u) for u > 0 otherwise, …) in double precision, once along +x and once
  along −x, which gives both one-sided derivatives. At the kink of `abs`, `min`
  or `max` it applies the one-sided rule (|u′|; the smaller or the larger of the
  two derivatives), which is exact for a function made of smooth pieces, so
  `x*abs(x)` has slope 0 at 0. An exponent counts as constant only when it does
  not read x, never because its derivative happens to be 0 at the mark.
  `func.readouts.slope` refuses, in this order: a mark that is not on one drawn
  piece; a mark where some operation has no finite value; a kink, pole or domain
  edge within a probe (1/1024 of a sampling interval) of the mark; and one-sided
  derivatives that are not the same finite number of at most 10¹² in size. The
  probe check is certified, not sampled. Interval arithmetic, rounded outward as
  for an area, runs over each half of the probe interval, [m − probe, m] and
  [m, m + probe], and must enclose every operation there. What each kink, pole
  or domain edge is measured by (an `abs` argument, the difference of a
  `min`/`max` pair, a divisor, a `sqrt`, `ln` or `log` argument, 1 − |u| for
  `asin` and `acos`, cos u for `tan`, the base of a power) must stay strictly on
  its side at the mark over both halves. So a corner or pole within a probe is
  refused even when the curve is back on the same side at both probes:
  `abs(sin(x))` at 3.14159, and `1/(x - 0.00001)` and
  `abs((x - 0.000003)*(x - 0.000006))` at 0. An operation exactly at its kink at
  the mark must not cross it within either half, so the mark is its only
  crossing there, and the one-sided rules decide: `x*abs(x)` at 0 passes,
  `x*abs(x*(x - 0.000003))` at 0 does not. The derivative rule refuses every
  corner, however small (`abs(x)` or `100 + abs(x)/10000000` at 0,
  `min(x, x^3)` at 1), a cusp (`sqrt(abs(x))` at 0), a vertical tangent
  (`sqrt(x)` at 0) and the edge of a domain, where no first-order rule applies:
  `sqrt(x^4)` and `(x^2)^1.5` at 0 are refused although their slope there is 0.
- `area` is the signed integral of the analytic curve, ∫ f(x) dx over the shaded
  interval. First, interval arithmetic certifies that f is continuous on the
  whole interval and stays in the y range. A cell is certified when an enclosure
  of f over it exists (no divisor range that holds 0, no pole of `tan`, no
  argument outside a domain) and lies within the y range widened by 1 % of its
  height: the drawing tolerance (`MGLimits.funcTolerance`), which also keeps a
  curve that touches the edge of the range from being refused for the overestimate
  of interval arithmetic. Any other cell is halved, depth first, at most 10 times
  (cells down to 1/1024 of the interval), within a budget of 256 enclosures per
  area (`MGReadout.certifyDepth`, `MGReadout.certifyBudget`). A cell still not
  certified is `func.readouts.area` when it has no enclosure (a singularity, even
  one between every sample, as `0.000001/(x - 0.3)` over [0, 1]) and
  `func.readouts.view` when its enclosure leaves the range (a spike between
  samples); running out of budget is `func.readouts.area`. A removable
  singularity (`sin(x)/x` over an interval that holds 0) cannot be certified and
  is refused too. Every interval operation rounds outward, so an enclosure holds
  the analytic curve (its literals, `pi` and `e` being the doubles they parse
  to), not only its evaluation in double precision. `+`, `−`, `×`, `÷` and whole
  powers move a bound to the next double outward exactly when the bound is not
  exact (TwoSum and a fused multiply-add find the rounding error), so an exact
  bound stays exact and `sqrt(1 - x^2)` over [−1, 1] still certifies. A library
  function's bounds widen by 4 ulps (`MGExpression.libraryUlps`), a margin over
  its 1–2 ulp error, within the function's range. An interval that may hold a
  pole of `tan` or a peak of `sin` or `cos`, allowing for the rounding of π,
  counts as holding it, and a bound that is not finite refuses. So
  `1/(((10^20 + x) - 10^20) + 1)`, which is 1 everywhere in double precision,
  is refused over [−2, 2]: its analytic divisor x + 1 is 0 at −1. Then the
  composite 5-point Gauss–Legendre rule (exact for polynomials up to degree 9 on
  each panel) on 128 equal panels of the shaded interval. Its error estimate is
  the difference from the same rule on 64 panels, and `func.readouts.area`
  refuses it unless the estimate is at most half of the last shown digit, the
  same two rules applied to |f| agree to that or to 1/1024 of their result,
  whichever is larger, f has a value at every node and at both ends, and the size
  is at most 10¹². The sampler's break detection has already run: a gap or pole
  it finds inside the shaded interval is `func.shade`. Last, `func.readouts.view`
  refuses an area when y = 0, or any sampled value (every node of both rules and
  both ends), is outside the y range, where the drawn band would be clipped.
- The drawn band is an approximation of the region measured, not the region
  itself: it fills between y = 0 and the sampled polyline, clipped to the y
  range (`MGGraph.shadeBands`), so it is a clipped, piecewise-linear picture of
  the analytic curve the readout integrates. The certification keeps the curve
  within the drawing tolerance of the range, and `func.detail` keeps the
  polyline within 1 % of the frame height of the curve at every sampling
  midpoint.
- Accuracy: a shown slope is the derivative at the mark up to double rounding.
  A shown area is within one unit of its last shown digit of the exact value as
  far as its error estimate holds: on a certified continuous curve, two rules
  that agree can still both miss a feature narrower than a panel. The golden
  cases include one whose real error is known: `sqrt(x)` on [0, 4], an endpoint
  with a vertical tangent, is off by about 3.5 × 10⁻⁶ with an estimate of
  6.4 × 10⁻⁶. The rule's samples are values in double precision, like the drawn
  curve: the certification bounds the analytic curve but not their rounding
  error, so where an expression cancels catastrophically inside the y range
  (`(10^20 + x) - 10^20` with a y range of ±20,000) the area shown is that of
  the curve as drawn.
- Step edits re-check the item as before, and an edit may change anything
  (colour, labels, even `a`) as long as every readout the scene names keeps its
  number (`func.readouts.edit`), because the text is filled once. A `set` patch
  parses the whole scene again, so the readouts and every text that names them
  are computed again.
- Cost: an area is at most 256 enclosures (one interval pass of the expression
  each) and 962 evaluations; a slope is one forward-mode pass at the mark (about
  three evaluations' work) and two interval passes. An interval pass is a
  bounded multiple of an evaluation: a product or quotient rounds its four
  corners both ways (eight operations with a fused multiply-add each), and a
  whole power squares once per bit of its exponent (at most about 1,100 times).
  So six graphs with every readout add at most 6 × 258 = 1,548 interval passes
  and 6 × 965 = 5,790 evaluations' work to a parse (`MGLimits.readouts`,
  `MGLimits.readoutPanels`, `MGReadout.certifyBudget`). A moving graph has no
  readouts; replaying a step edit of a graph that has them computes them again.
  `MGDescribe` speaks the numbers ("… shaded from x = 0 to 3.14 (signed area 2),
  marking the point (1, 0.84) where the slope is 0.54"), and
  `MGGrammar.document()` lists the names under `expression.readouts`.

[Copy the calculus scene](fixtures/v1/calculus.scene.json). The
[readout cases](fixtures/v1/readouts.cases.json) hold closed-form derivatives and
readouts, refusals and filled texts; `ReadoutCaseTests` checks them against the
parser and `tools/tests/test_mg_expr.py` against the offline mirror.

Not checked: whether a readout is the number a lesson needs, or the words around
it. No tangent line is drawn: the numbers go into text only.

## Explainer boards

An [explainer document](EXPLAINER.md) embeds a v1 scene as its `board`. The wire format does not change: a board is
an ordinary scene without `steps`, `title` or `"dim": "3d"`, parsed by `MGParser`. Inside an explainer only, the parser
gets an internal parse environment: a placeholder name with a dot (`{p.teeth}`) or a modifier is filled from the
explainer's 3D facts, and text limits apply to the filled text (the raw text is capped at four times the limit). With
no environment every result and reason is byte-identical (test B1). `MGParser.scene` refuses an explainer document
itself with `scene.unknown.<keys>`. `MGRenderInput.tableRows` and `tableCells` emphasise table rows and cells (an
explainer beat's `highlight` of `t.r2`); both are empty by default.

## Template parameters and what-if patches

Record-list parameters and the opt-in `shortest_path` template are additions
included in `v0.1.0`. Wire `v: 1` is unchanged: every shape
below is ordinary JSON inside the existing `params` object.

| Shape | Declaration | Wire form | Absent key |
| --- | --- | --- | --- |
| Number | `MGParamSpec(name:unit:range:integer:)` | finite number in range | `template.<p>.missing` |
| Optional number | same, with `defaultValue` (`.infinity` = optional) | finite number in range | default used |
| Number list | same, with `count` | array of numbers | `template.<p>` |
| Number list with default | same, with `count` and `listDefault` | array of numbers | default used |
| Record list | `MGParamSpec.records(_:count:fields:)` | array of arrays, one number per field, in field order | empty when `count` starts at 0, otherwise `template.<p>.missing` |

Numbers must be JSON numbers: a JSON boolean or string is rejected, never
coerced, so a 0/1 flag such as `shortest_path`'s `directed` must be `0` or `1`
(`true` gives `template.directed`). Values are range-checked inclusively and
rejected, never clamped. A record list reports `template.<p>.count`,
`.arity`, `.<field>` (type or range) or `.<field>.integer`. Number lists keep
their existing absent-key rule; only record lists treat absence as empty.
`MGParamSpec.isRecordList` distinguishes the two list shapes, because record
specs also set `count`.

A `listDefault` must fit the list's `count`, `range` and `integer` rule and is
only allowed on a number list; pack validation refuses any other default
(`MGPackError.badParamSpec`), and a template parsed without registration rejects
it lazily as `template.<p>.default`. `MGParamSpec.doc` shows a default as
`=[1,2]` and says `numbers` for a non-integer list.

Record-list declarations are checked when a pack is validated or registered
(`MGPackError.badParamSpec`): `count` within 0…`MGLimits.records` (32),
1…`MGLimits.recordFields` (6) fields with unique lowercase identifier
names that are not reason suffixes (`arity`, `count`, `integer`, `missing`,
`spec`), finite ranges, and a parameter name used once. A template parsed
without registration checks individual record declarations lazily as
`template.<p>.spec`; duplicate parameter names are checked only at registration.
`MGGrammar.document()` lists a `records` shape (`name`, `count`, per-field
`name`/`range`/`integer`) only for templates that declare record lists, so the
default document is unchanged. Cross-field rules are not in the grammar.

A template may give a specific cross-field rejection: its `reject` closure
returns a suffix such as `edges.loop`, reported as `template.edges.loop`
(lowercase dotted words, at most 48 characters; anything else becomes
`template.check`). `check` still reports the generic `template.check`.

A template's `make` may also throw. A thrown `MGError` whose reason is
`template.<suffix>`, with a suffix that follows the `reject` rule (lowercase
dotted words, at most 48 characters), is reported as is. Any other thrown
reason (another prefix, free or long text) and any other error, like a nil
result, is reported as `template.build`, so a template cannot report a reason
of another family such as `scene.version`.

### Raw templates (free-form params)

`MGTemplate(name:summary:paramsDoc:sample:compile:)` declares a template whose
`params` object is free-form JSON: strings, nested lists and objects that the
numeric shapes above cannot express. The engine checks only that every number
is finite (`template.params.number`), the nesting (at most `MGLimits.depth`,
64 levels, else `template.params.depth`) and the size (at most
`MGLimits.rawParamsBytes`, 4 KiB canonical, else `template.params.bytes`) and
passes the whole object to `compile`, which validates it and throws an
`MGError("template.<suffix>")` or returns nil to reject (same thrown-reason
rule as above). Everything it builds gets the wire checks.
Prefer declared parameters (including record lists) when the values are
numbers: they are validated before your code runs and appear in the grammar.
`paramsDoc` is a one-line schema for host documentation; `sample` is a params
object that should compile; `isRaw` tells the two template forms apart, and
`MGGrammar.document()` adds `rawParams` (`doc`, `maxBytes`) only for raw
templates, and `listDefaults` (parameter name → default list) only for
templates that declare a number-list default. A `params` patch merges top-level keys of a raw template's object
shallowly, exactly as below.

### Host access and unregistered templates

`MGPacks.builtIn` and `MGPacks.all` list the compiled-in and the registered
packs. `MGTemplate.validate(_:)`, `compile(_:is3D:)`, `paramsDoc` and `sample`
are public so a host can check example parameters (for example, before quoting
a sample in its own documentation). `compile` runs `validate` first, so it never
runs template code on unchecked params; its output is unchecked until the
parser re-validates it. `MGParser.scene(data:extraTemplates:)` (and the `object:` and
`json:` forms) and `MGScene.applying(_:extraTemplates:)` parse and patch with
templates that are not registered, for example to check a pack before
`MGPacks.register`. A registered template with the same name wins; extras are
never registered. `MGPatch(ops:baseRevision:)` builds a patch in code (for
example, a host slider); `applying` checks it with the `parse` rules (1–12
operations, finite numbers, each operation's keys, the 4 KiB bound) before it
re-validates the whole scene.

JSON has no NaN or infinity, so an `MGJSON` value built in code that holds one
is refused before it is measured or encoded: `scene.number` from
`MGParser.scene(json:)`, `patch.number` from `MGPatch.parse(json:)` and from
`applying` a code-built patch, and `template.params.number` from a raw
template. `MGJSON.isEncodable` reports this; `canonicalByteCount` is `Int.max`
for such a value, so no byte bound treats it as small.

JSON nests at most `MGLimits.depth` = 64 levels (arrays and objects on one
path; `[[1]]` is 2) at every entry point. Real scenes and patches nest 6 to 15
levels. The system JSON parser and encoder, `MGJSON(any:)`, and Swift's `==`,
hashing and freeing of nested values all recurse once per level. At 64 levels
the deepest of them (a sorted-key encode of nested objects) uses less than half
of a 512 KiB thread stack (iOS secondary threads) and about a fifth of the
1 MiB iOS main-thread stack; a few hundred nested objects can overflow them.
So every entry point counts the nesting first, without recursion: on JSON
`Data` before the system parser (`scene(data:)`, `MGPatch.parse(data:)`, the
stream parser), and on a value built in code before anything reads, compares or
encodes it.

JSON `Data` must be UTF-8. The system parser also reads UTF-16 and UTF-32
(without a byte order mark), which the nesting counter cannot read. So every
`Data` entry point refuses bytes that are not valid UTF-8, or that hold a raw
NUL byte (valid UTF-8 JSON never does; UTF-16 and UTF-32 JSON always does),
with its `json` reason (`json`, `patch.json`) before the parser runs. A deeper value is `scene.depth`, `patch.depth` or
`template.params.depth`. For a value built in code the reasons come in this
order: `.number`, `.depth`, then the byte bound. `canonicalData` and
`canonicalByteCount` never encode a deeper value (`Int.max`), and
`MGJSON(any:)` returns nil for one. Do not compare, hash or convert
(`MGJSON.any`) a deeper value yourself; give it to an entry point, which
refuses it. Lessons and [Solid 3D](SOLID-3D.md) use the same cap (see
[lessons](LESSONS.md)).

The `params` patch operation merges **shallowly**, one top-level key at a time:

- A key that is not sent keeps its previous value.
- A sent list or record list **replaces the whole list**; there is no
  per-element edit. To change one link's weight, send every link.
- `null` is not a deletion. It is rejected (`template.<p>`) like any other
  wrong type, and the previous scene stays.
- A key cannot be removed once set. An optional record list is cleared by
  sending `[]` when its count allows 0. An optional number (for example
  `target`) cannot be cleared by a patch; send a fresh scene.
- The whole scene is rebuilt and revalidated, including author `title`, `over`,
  `hide` and wire `steps`. If any of them no longer fits the recomputed scene,
  the patch is refused whole.

### Opt-in graph pack: `shortest_path`

`MGGraphPack` is not built in. A host that wants it calls
`try MGPacks.register(MGGraphPack.pack)` once per process (a second call throws
`duplicatePack`); until then the template is `template.unknown`.

```json
{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,2],[1,2,2],[0,2,4]],"target":2}}
```

[Copy the scene JSON](fixtures/v1/shortest-path.scene.json). After registration
it narrates "A shortest path 0→2 costs 4. 2 routes tie at 4; the one found first
is shown." The [whole-list edges patch](fixtures/v1/shortest-path-edges.patch.json)
makes 0→1→2 the only route at 3; the [null patch](fixtures/v1/shortest-path-null.patch.json)
is refused with `template.target`.

The standalone `marty-scene-validate` CLI does not register this opt-in pack,
so it rejects these scenes. Validate them in a host that explicitly registers
`MGGraphPack.pack`; the examples are not CLI-supported fixtures.

- `n` 2–8 nodes; `edges` 1–16 records `[a, b, w]` with integer `w` 0–99;
  optional `source` (default 0), `target`, `directed` (0/1) and `at`
  (none, or exactly one `[x, y]` per node, x 0.5–11.5, y 2–7.5).
- One edge per unordered node pair, also when directed, so anti-parallel arcs
  (a→b 3 and b→a 7) are not expressible. This is bounded directed shortest
  paths, not general directed-graph support.
- Specific rejections: `template.edges.node` (index ≥ `n`), `.edges.loop`,
  `.edges.duplicate`, `.source.range`, `.target.range`, `.target.integer`,
  `.at.count`, `.at.gap` (authored nodes closer than 1.2), `.at.crossing` (an
  edge within 0.6 of a node that is not one of its endpoints, so it would read
  as two links). Geometry comparisons allow 1e-9 for decimal representation.
  3D scenes are refused (`template.build`).
- Item ids are semantic: node `n<i>`, the distance array `dist`, an undirected
  link `e<min>_<max>` and a directed arc `d<tail>_<head>`. Reordering records
  (or swapping an undirected link's endpoints) keeps ids, `over`/`hide`
  entries and step references on the same link. Removing a link, reversing an
  arc or toggling `directed` changes the id, so an `over`/`hide` entry naming
  the old link is refused (`over.ref` / `hide.ref`), never moved. There is no
  patch operation to clear these entries: load a fresh scene to remove them
  before changing that link's identity.
- Hiding a template item that the walkthrough edits is refused by the existing
  step-edit reference check; this pre-existing engine behavior is unchanged
  here. Prefer a `params` what-if to hiding links.
- Computed placeholders: `{n}`, `{m}`, `{reached}` always; `{cost}` and
  `{routes}` (number of shortest simple paths, with no repeated node) only
  when a target is set and reachable. Author text that uses `{cost}` or
  `{routes}` makes a disconnecting what-if fail with `title.placeholder.cost`
  (or the field that quotes it), and the previous scene stays.
- Narration discloses equal-cost relaxations into unsettled nodes as "ties …,
  earlier route kept". It does not enumerate ties into already-settled nodes.
  Summaries separately count shortest simple paths, including alternatives
  through zero-weight arcs into settled nodes. When several paths share the
  shortest cost the summary says "A shortest path … N routes tie" instead of
  "The shortest path". A target equal to the source is narrated as a
  zero-cost path to itself. A tree-only summary also discloses alternative
  shortest simple paths, without treating zero-weight cyclic walks as
  additional paths.
- Not accepted: dense automatic layouts (with an even `n`, diameter chords
  share one midpoint, so weight labels can overlap; pass `at`), colour-only edge
  state, accessibility, and frame cost of per-frame step-edit replay.

## Swift API at a glance

| Task | Public entry point | Contract |
| --- | --- | --- |
| Parse a full scene | `MGParser.scene(data:)` → `Result<MGScene, MGError>` | Validate before rendering; failure supplies a developer diagnostic. |
| Inspect structure | `MGGrammar.document()` → `[String: Any]` | Derived keys, kinds, colors, templates and selected bounds; semantic checks remain in the parser. |
| Parse/apply an edit | `MGPatch.parse(data:)`, `scene.applying(_:)` | Atomic validated replacement; preserve the old scene on failure. |
| Host live updates | `MGSceneController`, `apply(patch:requireRevision:)` | Main-actor owner; require the current scene revision for untrusted updates. Controller returns success/failure, not an error-code payload. |
| Receive chunks | `MGStreamParser.feed(_:)` / `finish()`; controller stream methods | Previews are provisional; final strict validation decides acceptance. |
| Present native UI | `MartyGraphicsView(scene:)` / `(controller:)` | SwiftUI host supplies lifecycle, controls and text alternatives. |
| Draw deterministic frames | `MGTimeline.items` / `frame`, `MGViewport`, `MGCanvasRenderer` | See the complete [native exporter](../Examples/Showcase/Sources/MartyShowcase/Showcase.swift). |
| Extend templates | `MGTemplate`, `MGPack`, `MGPacks.validate` / `register` | Validate bounded output, fixtures, patches and fail-safe cases; registration is atomic. |
| Check a pack before registering | `MGParser.scene(data:extraTemplates:)`, `scene.applying(_:extraTemplates:)` | Extras are used for one call only; a registered name wins. |
| Build a patch in code | `MGPatch(ops:baseRevision:)` | `applying` checks it with the `parse` rules, then re-validates the whole scene. |

Copyable parse/patch flow (in a host that imports Foundation and MartyGraphics):

```swift
let scene = try MGParser.scene(data: sceneData).get()
let patch = try MGPatch.parse(data: patchData).get()
switch scene.applying(patch) {
case .success(let updated):
    // Present updated; its scene revision has advanced.
    print(updated.title)
case .failure(let error):
    // Keep scene. Map diagnostics to your own safe user-facing message.
    print(error.reason)
}
```

Load `sceneData` and `patchData` from the two linked UTF-8 JSON files. For actor
ownership, streaming and the native view, continue in the [tutorial](GETTING-STARTED.md).

## Developer error reasons

`MGError.reason` is a developer/test diagnostic, not learner-facing copy. This is
a selected v1 reference, not an exhaustive stable error enumeration; dynamic
suffixes can identify the rejected key or ID. Match only what your integration
has tested, and handle an unknown reason by keeping the previous valid scene.

| Reason / family | Trigger | Recovery |
| --- | --- | --- |
| `json`, `patch.json` | Input decoding, malformed JSON, `Data` that is not UTF-8 (for example UTF-16), or raw input headroom exceeded | Send a complete, bounded inner object; do not feed a transport envelope to the parser. |
| `scene.version` | `v` differs from 1 | Negotiate/support the protocol version before sending scenes. |
| `scene.unknown.<keys>` | Closed root object has unsupported keys | Remove unsupported fields; [negative fixture](fixtures/v1/unknown-key.scene.json). |
| `scene.bytes`, `patch.object`, `items.count`, `steps` | Canonical object or collection violates bounds | Reduce authored content; `patch.object` also covers a non-object patch. |
| `template.unknown`, `template.params` | Missing/unregistered template or invalid parameter object | Use the registered public templates and their declared parameters. |
| `template.<p>`, `template.<p>.missing` / `.count` / `.arity` / `.<field>` / `.integer` | A parameter has the wrong type (including `null`), is absent, or a value or record is out of its declared shape | Send the declared shape; see [template parameters](#template-parameters-and-what-if-patches). |
| `template.<p>.spec`, `template.<p>.default`, `template.check`, `template.<rule>` | Out-of-contract record declaration or list default, generic cross-field failure, or a template's specific cross-field reason | Fix the pack declaration, or correct the named parameters. |
| `template.params.bytes`, `template.build` | A raw template's params object is over 4 KiB, or a template returned nil, threw a non-`MGError` error or threw a reason outside `template.<suffix>` | Send a smaller object; check the template's own documentation. |
| `scene.number`, `patch.number`, `template.params.number` | A value built in code holds NaN or an infinity | Send finite numbers. |
| `scene.depth`, `patch.depth`, `template.params.depth` | JSON text or a value built in code nests deeper than `MGLimits.depth` (64 levels) | Send a flatter value; real scenes and patches nest 6 to 15 levels. |
| `3d.text.code` | `code` text in a 3D scene | Use plain text in 3D, or keep the scene 2D. |
| `table.cells`, `table.cell`, `table.marked`, `region.pts` | A table shape, cell or mark, or a region's points, is out of bounds | See [tables, regions and code text](#tables-regions-and-code-text). |
| `func.y`, `func.y.syntax` / `.tokens` / `.depth` / `.name` / `.arity` / `.var.<v>`, `field.dx…`, `field.dy…` | An expression is not text, too long, outside the grammar or its bounds, names an unknown function, or reads a variable the item does not provide | See [function graphs, vector fields and text alternatives](#function-graphs-vector-fields-and-text-alternatives). |
| `func.detail`, `func.breaks`, `func.empty`, `func.shade`, `func.mark`, `func.loop`, `func.period`, `field.n`, `field.style`, `field.empty`, `items.expr` | The graph cannot be drawn faithfully (aliasing, too many breaks, nothing visible), a shaded interval or marked point does not fit, a loop is not seamless, a grid or style is out of range, or a scene has more than 6 graph checks (graph items, plus step and `over` edits of them) | Change the range, the expression or the keys named by the reason; for `items.expr`, use fewer graphs or fewer edits of them. |
| `func.readouts`, `func.readouts.period` / `.mark` / `.shade` / `.slope` / `.area` / `.view` / `.edit`, `<text>.placeholder.readout` | A readout list is malformed, asked of a moving graph or without its `mark` or `shade`; a slope is not proven (a corner, cusp, vertical tangent, pole or domain edge at the mark or anywhere within a probe of it, even one the curve crosses back over before the probe); an area's analytic curve cannot be certified continuous and inside the y range within its budget (outward-rounded interval arithmetic, so a pole that cancellation hides in double precision counts), or the area cannot be computed to its shown digits, or a sample of it is outside the y range; a step edit changes a readout the text names; a text names a readout the scene does not compute | Move the `mark` more than a probe (1/1024 of a sampling interval) from every corner, pole and domain edge; shade an interval where the analytic curve is continuous and inside the y range (or widen `yr`), and write the expression without cancelling large terms (`x + 1`, not `((10^20 + x) - 10^20) + 1`); see [readouts](#readouts-slopes-and-areas). |
| `alt`, `step.alt`, `template.alt` | A text alternative breaks the plain-text rules | Use plain text of at most 200 characters. |
| `sliders`, `slider`, `slider.missing`, `slider.unknown.<keys>`, `slider.param`, `slider.duplicate.<p>`, `slider.min`, `slider.max`, `slider.range`, `slider.step`, `slider.step.count`, `slider.grid`, `slider.default`, `slider.label`, `slider.label.placeholder` | A slider list or slider is out of shape, or its range or step is out of bounds; a stop's label (an end's included) does not read back as exactly the value the engine would get, or its stops are too close to tell apart (`slider.grid`); its default is not exactly the value of a stop (`slider.default`); or its label is not fixed plain text | See [learner sliders](#learner-sliders); `MGRepairHint.text(for:)` gives a one-line fix. |
| `slider.unbound`, `slider.field`, `slider.default.<id>`, `slider.edit`, `sliders.bindings`, `slider.<p>.min.<reason>`, `slider.<p>.max.<reason>` | No `func` sets the parameter, a `field` or a step edit sets it, a `func` sets another value, too many slider-graph pairs, or a driven graph fails a check at an end of the range | Set the parameter on the graphs to the default, remove the conflicting key, or narrow the range. |
| `vector.on`, `edge.nodes`, `highlight.target` | Reference is absent, has the wrong kind, or highlights itself | Fix references before applying the scene. |
| `highlight.cycle` | An indirect highlight chain loops | Make the chain terminate; [negative fixture](fixtures/v1/highlight-cycle.scene.json). |
| `patch.stale`, `patch.rev` | Revision mismatches or is invalid | Rebase the intended change on the current scene revision; do not retry stale content blindly. |
| `patch.op.<name>`, `patch.<op>.missing`, `patch.set.ref`, `patch.step.range` | Unsupported operation, missing operation key, missing set target or absent scene step | Correct the operation/target/index, then validate the entire patch again. |

Unsupported operation names outside 1–24 ASCII letters, digits or underscores are reported as `patch.op.?`.

The [protocol fixture test](../Tests/MartyGraphicsTests/ProtocolFixtureTests.swift)
checks the linked JSON, exact selected error reasons, successful title edit and
stale-patch rejection. It passed in the actual 24-test Mac run at
`e1367c946171584044bacf5649ec7f816ecb72ae` (2026-11-04, macOS 26.6.2 arm64,
Apple Swift 6.3.3; dump-package/valid JSON, build and test all exit 0).
That local-package result is not remote-install, release or device acceptance.
Later documentation-only changes can reuse it only with unchanged Swift/package/
test/fixture bytes; retain the original execution SHA rather than relabeling a build.

## Bounds and platforms

The [validator constants](../Sources/MartyGraphics/MGParser.swift) are authoritative.
Byte limits apply to canonical JSON; raw decoder headroom is twice the byte bound.

| Surface | Current bound |
| --- | --- |
| Scene / patch | 8 KiB / 4 KiB canonical UTF-8 JSON; patches have 1–12 operations |
| Items | 24 full-scene wire items; 10 template extras; 40 resolved total |
| Steps | 8 wire-authored; 48 template-built; 6 edits and 16 shown IDs per wire step |
| World | Width and height each 2…100; default 12 × 8 |
| Text lengths | Title 60, label 40, text 120, narration 200 |
| Geometry | Plot/path points up to 64; rope points up to 6 |
| Collections | Array 16 cells / 4 pointers / cells up to 6 characters (a number counts its displayed text, so `-123456` is refused); 6 bars / 16-character bar labels; 8-character node text; table 8 rows × 6 columns / cells up to 12 characters; region 3–64 points |
| Graphs (new kinds only) | 6 graph checks per scene (each `func` / `field` item, and each step or `over` edit of one); expressions 80 scalars / 48 tokens / 8 nested parentheses; `func` 257 samples, 16 breaks, 1 % of the frame height; `field` 2–16 × 2–12 arrows; parameters ±1,000; `period` 0.5–20 s; `alt` 200 characters; `func` readouts 3, an area on 128 panels (962 evaluations) |
| Sliders (new key only) | 3 per scene; range within ±1,000; at most 100 steps; 6 slider-graph pairs; labels 40 characters |
| Raw template params | 4 KiB canonical `params` object |
| Nesting (arrays and objects on one path) | 64 levels (`MGLimits.depth`); lessons 59 per statement |
| Lesson `animate` | 2 per beat and per host `apply` batch, 24 per stream (`lesson.animate.count`); see [lessons](LESSONS.md#limits-and-reasons) |

Preserve bounds and rollback. Expansions need an actual use case, boundary/failure
tests and measurements; see the [limits rationale](CAPABILITIES.md#bounds-are-part-of-the-contract).

| Target | Declaration / evidence |
| --- | --- |
| macOS | Declared macOS 14+, Swift tools 6.0, Swift language mode 5. The capture receipt records 95 tests plus showcase export at its capture source; the separate local-package run at `e1367c9` passed 24 tests, including the new protocol fixtures. Neither establishes interactive or device acceptance. |
| iOS / iPadOS | Package declares iOS 17+; SwiftUI/SceneKit renderer. No physical iOS-device or accessibility acceptance is established by the Mac export receipt. |
| Windows / Linux / browser | This Apple-framework package is unsupported there. Portable-core/browser implementation is planned-not-started; no architecture rewrite or cross-platform delivery is selected. |

The [public-versus-app matrix](CAPABILITIES.md) distinguishes engine primitives
from hosted services, app content and browser recreations. SceneKit 3D has a
bounded primitive subset; these 2D fixtures are not 3D quality evidence.

## Experimental, opt-in `layer2d` programmatic video

Phase 1 is on `main`. It is not in a tagged release and is not a stable protocol. Use
`MGParser.scene(data:programmaticVideo:)` (also `object:` and `json:`) with `true`.
The default parser entry points and an explicit `false` take the original code path:
`layer2d` still refuses with `scene.unknown.layer2d` (existing size/depth checks retain
their precedence). Opt-in scenes without `layer2d` also use the legacy parser.

The closed envelope and field bounds are the [draft schema](schemas/scene-2d-layer.draft.schema.json).
Standalone core v1 scenes are described by the [core scene draft schema](schemas/scene-v1.draft.schema.json).
Phase 1 accepts only that minimal envelope: `v: 1`, `dim: "2d"`, a title of 1–80
Unicode scalars, empty `items`, and `layer2d`. It does not compose legacy items,
templates, world, camera or steps. Unknown versions fail closed. Status remains
`proposed` and version `0.1.0-draft` to preserve the three original example files.
The library bundles an identical schema resource and validates its supported
schema vocabulary before decoding; a test compares both copies byte-for-byte.

Bounds: UTF-8 and canonical JSON ≤64 KiB, nesting ≤16, 64 elements and tracks,
120 keys/track, 1–1,800 source frames at exactly 30 fps, 60 captions, canvas
320–1,920 × 180–1,080. Text work is capped at 8,192 authored Unicode scalars and
4,000,000 scalar-frames. Schema bounds also apply to coordinates, colors, line
counts, IDs, sizes, fonts, tick counts and strings. Text is literal, never evaluated
or placeholder-expanded; URL schemes, markup and control/bidi characters refuse.
Code allows comparisons and braces, but not markup. No files or URLs are read
from scene fields. Local output destinations are supplied by the host, not JSON.

Coordinates are canvas pixels, right/up, origin bottom-left. Shapes are centered;
labels are centered; a code block starts at its top-left and extends down.
Axes/number lines start at their lower-left, with uniformly spaced tick values
including both endpoints. Tick numbers use a pinned POSIX formatter (4 significant
digits). Axes ranges must increase. Code highlight is 1-based; 0 means none.
`MGTimeline.videoFrame(_:in:)` resolves independent sparse position and opacity
keys with linear or hold interpolation. Before a property's first key its element
value is used; after its last key that value holds. Highlights always hold.
Tracks have unique existing targets; keyframes strictly increase and precede
duration. Captions are ordered, nonoverlapping half-open frame intervals.

Parsing preflights every source frame before a checked plan can escape. Measured
text, arrow extents and tick labels must fit with 8-pixel margins outside the bottom
96-pixel caption/provenance band. Captions wrap to at most 52 pixels of height;
the generated-media label is always visible. Text/tick collisions refuse; text
draws above geometry on a contrasting backing. Shape overlaps are warnings, not
algorithmic errors. Checks prove bounded structure/layout, not educational truth.
Stable refusal families are `video2d.schema.<JSON path>`, `video2d.version`,
`video2d.target`, `video2d.frame`, `video2d.range`, `video2d.highlight`,
`video2d.text`, `video2d.layout`, `video2d.budget`, and `video2d.export`.

```swift
let scene = try MGParser.scene(data: data, programmaticVideo: true).get()
let plan = try MGProgrammaticVideo.check(scene, programmaticVideo: true)
let image = try MGProgrammaticVideo.frame(0, in: plan)
let receipt = try await MGProgrammaticVideo.export(
    plan, to: hostGrantedLocalURL,
    options: MGVideoExportOptions(format: .mp4, burnCaptions: true, writeSRT: true),
    programmaticVideo: true)
```

`MGCheckedVideoPlan` has no public constructor. The canvas renderer and library
frame/export API share the checked native CoreGraphics/CoreText drawing path.
`MGVideoExportReceipt` reports dimensions, fps, frame count, duration and overlap
warnings. An optional host progress callback receives completed/total frames.
There is no app feature, new template, remote renderer or code execution.

MP4 uses H.264 at 30 fps and integer `CMTime(frame, timescale: 30)`, even canvas
dimensions (odd sizes refuse), tagged sRGB/BT.709, readiness timeout/backpressure,
and an eight-buffer pixel pool allocation limit. Encoder readiness and pool
allocation waits time out after 10 seconds with `mp4: writer stalled`; failed
exports cancel the writer and remove their partial files. `MGMovieWriter` is shared with
the Solid3D CLI (its existing even-size rounding and frame rates are retained).
GIF samples every third source frame at 10 fps, limits duration to 450 source
frames divisible by three, and scales the longest edge to at most 640 pixels.
ImageIO receives frames sequentially; no full-video frame array is built. Its
internal buffering and iPad incremental memory/time targets are **not measured**.

Both formats default to burned captions plus an SRT sidecar; either can be
disabled independently. SRT endpoints round integer frame times to milliseconds.
The generated-media label cannot be disabled. Export checks Swift task cancellation
between frames and during MP4 backpressure/finalization; ImageIO finalization is
synchronous and cancellation is checked immediately afterwards. A private partial
directory on the destination volume is removed on failure/cancellation. Completed
files publish by rename, never overwrite existing files, and roll back video if
sidecar publication fails. Two-file publication is not a filesystem transaction.
Use a background task from UI code; no simulator/signing or network is required.
