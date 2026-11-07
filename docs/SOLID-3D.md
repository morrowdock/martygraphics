# Solid 3D engine (preview)

The solid engine turns a small, validated JSON assembly into shaded mechanical
models: closed triangle meshes, kinematic joints, gear-mesh constraints, an
explode parameter and authored teaching steps. A SceneKit studio renderer draws
it with physically based materials and soft shadows; a plain-number snapshot
lets any other renderer draw the same frame.

It is a **schematic teaching engine**. Gear profiles are standard involute
proportions with backlash, sampled for display. The checks below are geometric
and kinematic; nothing here validates strength, wear, lubrication, efficiency or
manufacturability.

The example renders come from
[`planetary.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/planetary.json)
through `marty-solid3d --export`. See [the example README](../Examples/Solid3D/README.md).
Four of them are checked in under [`assets/solid/`](assets/solid/) (hero, labelled
exploded view, slider-crank section, loop GIF), with a render receipt in
[`assets/solid/provenance.json`](assets/solid/provenance.json): capture commit, source
file hashes, artifact hashes and the measured render time per frame.
A two-spool turbofan cutaway built with blade rows and capped partial revolves is in
[`Examples/Turbofan`](../Examples/Turbofan/README.md); it also shows the snapshot
path traced through a small adapter.

## Layers

| Layer | Files | Platform |
| --- | --- | --- |
| Geometry kernel | `Solid/MGSolidMath.swift`, `MGMesh.swift`, `MGProfile.swift`, `MGSolidBuilders.swift`, `MGGear.swift`, `MGSolidShapes.swift`, `MGSolidTurbo.swift` | Foundation only |
| Assembly and kinematics | `Solid/MGAssembly.swift`, `MGSolidModels.swift`, `MGSolidChecks.swift` | Foundation only |
| JSON format | `Solid/MGSolidParser.swift` | Foundation only |
| Components | `Solid/MGSolidComponents.swift`, `MGSolidBuiltInComponents.swift` | Foundation only |
| Honesty (facts, tiers, lints, read-back) | `Solid/MGSolidFacts.swift`, `MGSolidTiers.swift`, `MGSolidFrames.swift` | Foundation only |
| Annotations (labels, arrows, dimensions, placement, occlusion) | `Solid/MGSolidAnnotations.swift`, `MGAnnotationLayout.swift` | Foundation only |
| Snapshot export | `Solid/MGSolidSnapshot.swift`, `MGMaterial.swift` | Foundation only |
| Check report, render plan, reason catalog | `Solid/MGSolidReport.swift`, `MGSolidRenderPlan.swift`, `MGSolidReasons.swift`, `MGEngine.swift` | Foundation only |
| Studio renderer | `Solid/MGSolidRenderer.swift` | SceneKit, CoreGraphics, Metal |
| Annotation overlay | `Solid/MGSolidOverlayView.swift` | SwiftUI, CoreGraphics, CoreText |

Kernel space is millimetres with **+Z up** (gear axes along Z). The render world
and the snapshot are **Y-up** (`MGSolidStage.zUpToYUp`). Read
[Frames and the up convention](#frames-and-the-up-convention) before you place parts:
in recorded model runs, a child placed in world coordinates and a horizontal shaft
left vertical were the most common errors that the checker did not report.

## Frames and the up convention

| Item | Convention |
| --- | --- |
| Units and axes | Millimetres, right-handed, **+Z is up**. |
| Up | A joint axis `[0, 0, 1]` is **vertical** (a turntable, a helicopter rotor, a quadcopter prop). A **horizontal** shaft is `[1, 0, 0]` or `[0, 1, 0]` in world terms (a wind turbine, a car axle, an aircraft propeller, a gearbox on its side). |
| Built-in axes | `gear`, `ringGear`, `shaft`, `tube`, `hex`, `plate`, `carrier`, `extrudedProfile` (its depth) and `revolvedProfile` are built along their part's local **+Z**; `bladeRow` repeats around local +Z; `blade` spans local +X. To lay a part down, turn the **part** with `rot`: `"rot": [0, 1, 0, 90]` takes local +Z to world **+X**, `"rot": [1, 0, 0, -90]` takes it to world **+Y**. Keep the joint axis `[0, 0, 1]`: a joint axis is written in the part's own frame, so after that `rot` it is the world X axis, and gear checks need the joint along the gear's own axis (`constraint.gearMesh.joint`). |
| Frames | A part's `at` and `rot` are **relative to its parent's frame** (after the parent's own joint). A part without a `parent` is placed in the world frame. A shape's own `at` / `rot` (inside the shape entry) are relative to its part. A component `use` entry's `at` / `rot` place the component's root parts in the frame of its `parent`. **Never repeat the parent's position in a child.** |
| Positive rotation | Right-hand rule about the joint axis: seen from the tip of the axis vector looking back toward the origin, a positive drive turns counter-clockwise. "CW" and "CCW" in text mean as seen from that side. |
| Blades | Span +X, chord +Y at angle 0 with the leading edge toward −Y, angle = pitch + twist × t (see `blade` below). |
| Render and snapshot | Y-up (`MGSolidStage.zUpToYUp`); the kernel and the JSON stay Z-up. |

The double-offset error: the author knows the blade should sit at the hub, 50 mm out
along X, and writes that world position into the child.

```json
{"id": "hub", "at": [50, 0, 0], "shape": {"shaft": {"radius": 10, "length": 20}}},
{"id": "blade", "parent": "hub", "at": [50, 0, 0], "shape": {"box": {"size": [40, 8, 4]}}}
```

The blade lands at x = 100 mm (twice the offset). `marty-solid check` warns
`frame.child.absolute.blade`. The child's `at` is relative to the hub, so the fix is
`"at": [0, 0, 0]`. That warning is a guess from bounding boxes, and correct layouts can
trigger it (two plates with a gap, a plate on posts), so even `--strict` never refuses it.
The real defence is the read-back in the check report: it says, for each part, where it is
in the world and which way it turns, for example
`rotor: … turns about a horizontal axis (+X) …; child of tower (at [0, 0, 92] in the tower frame)`.
Compare it with what you meant before you answer. A v2 part can also state its intended
orientation, and the engine refuses the document when the model does not match:
`"expect": {"axisWorld": [1, 0, 0]}` (the joint axis in world space at input 0) or
`"expect": {"upWorld": [0, 0, 1]}` (the part's local +Z in world space); within 1°, sign
included (`expect.axis.<id>`, `expect.up.<id>`).

## Kernel

* `MGMesh`: welded indexed triangles. `edgeReport` checks that every edge is
  shared by exactly two oppositely wound triangles; `signedVolume > 0` checks
  outward winding. `renderMesh(creaseAngle:)` splits vertices only across sharp
  edges, so involute flanks shade smoothly and chamfers stay crisp.
* `MGProfile`: an outer loop and holes, orientation normalised. Caps are
  triangulated by a zipper merge for star-shaped annuli (gears, rings) and by ear
  clipping with hole bridging otherwise. The zipper keeps every triangle
  counter-clockwise (it never runs more than one step out of angle order to do
  so); if it cannot, the cap falls back to ear clipping.
* Builders: `extrude` (optional 45-degree chamfer on every cap edge), `revolve`
  (closed loops or open profiles with poles), `cylinder`, `tube`,
  `chamferedBox`, `hexPrism`, `blade` (NACA 4-digit style section, root pitch, linear twist
  and taper).
* Turbomachinery (`MGSolidTurbo.swift`): `bladeRow` repeats one airfoil blade
  N times around the Z axis. Each section lies on a cylinder of constant radius
  (as real blade sections lie on stream surfaces), so the tip radius is exact at
  every angle. `revolve(_:segments:closed:sweep:start:)` revolves a profile
  through part of a turn and caps both cut faces, so a cutaway casing shows a
  real solid wall section in any renderer.
* Gears: `MGSpurGear` (external involute, 20-degree default pressure angle,
  addendum 1 m, dedendum 1.25 m, elliptical root fillet) and `MGRingGear`
  (internal). `MGGearPhase` gives the tooth phase that makes two gears mesh.

## Assembly JSON (v1)

Closed keys, bounded numbers, resolved references. Any violation rejects the
whole document with a stable reason, for example `part.gear.teeth`,
`constraint.gearMesh.module`, `constraint.gearMesh.distance`, `joint.axis`,
`ref.unknown.<id>`, `part.unknown.<key>`, `constraint.underdetermined`,
`constraint.conflict` or `constraint.gearMesh.phase`. `MGSolidIssue.part` names
the part when there is one, so a generator can repair from the reason alone.
A missing required key is named, for example `part.drive.crankSlider.missing.radius,rod`, and unknown keys likewise (`….unknown.crankRadius`). A reason is always one token without spaces: author-supplied names inside it keep
ASCII letters, digits, `_` and `.` (other characters become `_`, at most 32), so
`"source": "x y"` reports `ref.unknown.x_y`. Checks run in document order (patch
part ids in sorted order), so the same input always reports the same first error.
A `parent` that contains a dot but names no part reports `ref.unknown.<id>` (for
example `ref.unknown.a.b`), also in documents without components; before components it
reported `part.parent`.

```json
{"v": 1, "kind": "assembly", "title": "…", "units": "mm",
 "params": {"input": 0, "explode": 0},
 "parts": [{"id": "sun", "name": "Sun gear", "material": "brass",
            "shape": {"gear": {"teeth": 24, "module": 2, "width": 14, "bore": 6}},
            "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1},
            "at": [0, 0, 0], "rot": [0, 0, 1, 0], "explode": [0, 0, 40], "explodeWindow": [0.2, 0.8]}],
 "constraints": [{"gearMesh": {"a": "sun", "b": "planet", "carrier": "carrier"}}, {"fixed": "ring"}],
 "steps": [{"say": "…", "highlight": ["sun"], "explode": 0, "camera": "hero", "orbit": 0, "spin": 1}]}
```

* **Part library** (`shape` is one primitive or an array of up to 8). Each entry is
  an object with exactly one key, the primitive name, whose value holds that
  primitive's fields plus an optional `at` (offset) and `rot` (axis-angle
  `[x, y, z, degrees]`) inside it, for example
  `{"shaft": {"radius": 4, "length": 10, "at": [18, 0, 0]}}`; a part's own `at` /
  `rot` sit next to `shape` and are relative to its parent's frame (see
  [Frames](#frames-and-the-up-convention)). Primitives: `gear`, `ringGear`, `shaft`, `tube`, `box`, `hex`,
  `plate` (disc with round holes), `carrier` (hub, arms and bosses with a smooth
  union), `extrudedProfile`, `revolvedProfile` (open with poles, or `closed`
  for walls such as casings and nozzles; optional `sweep` and `start` in
  degrees give a capped partial revolve for cutaways, with
  ceil(96 × sweep / 360) segments, at least 2), `blade`, `bladeRow`.
* **`blade`**: one airfoil along +X from `root` to `root + span`, with `chord`,
  optional `tipChord` (linear taper), `thickness` (chord fraction), `camber` (0–0.09,
  toward local +Z), `camberPosition`, `pitch` and `twist` (degrees, −80 to 80 each). The
  section at span fraction t is turned by **pitch + twist × t** about the span axis.
  At angle 0 the chord lies along +Y with the leading edge toward −Y; a positive angle
  turns +Y toward +Z. So a blade on +X moves leading edge first when its part turns
  about **−Z** (`"revolute": [0, 0, -1]` with a positive drive). For a propeller that
  pushes air toward −Z (thrust toward +Z), use a **negative `pitch`** (leading edge
  raised) and a positive `twist` that brings the tip angle toward zero: steep at the
  hub, flatter at the tip, for example `"pitch": -40, "twist": 28` (−40° at the root,
  −12° at the tip). |pitch + twist| ≤ 85 (`part.blade.twist`). The mesh is always
  15 sections of 56 points.
* **`bladeRow`**: `count` (2–128), `span`, `chord`, `root` (hub radius), and
  optional `z` (axial position of mid-chord), `thickness` (chord fraction),
  `stagger` (chord angle from the axis at the root, degrees; positive puts the
  trailing edge behind the leading edge for rotation toward +θ, as on a fan or
  compressor rotor), `twist` (extra stagger at the tip), `tipChord`, `camber`
  (signed; positive bows the blade toward +θ), `camberPosition`, `phase`,
  `sections` (2–24) and `chordSamples` (6–32). The leading edge points to -Z.
  Rejections: `part.bladeRow.count` (also when neighbouring blades would touch),
  `part.bladeRow.chord` (a section wraps too far round its cylinder),
  `part.bladeRow.twist`, `part.bladeRow.triangles` (over 250 000 per row) and
  one reason per out-of-range field. Blade rows and partial revolves count toward
  the mesh budget exactly (`MGShapeSpec.meshEstimate`).
* **Materials**: `brushedSteel`, `polishedSteel`, `darkSteel`, `blackOxide`,
  `brass`, `bronze`, `aluminum`, `rubber`, `glass`, `titanium`, `nickelAlloy`
  (warm, heat-tinted hot-section metal), `composite` (dark carbon fibre with a
  clear coat), `ceramic` (matte thermal-barrier coating), `anodized.<role>`,
  `plastic.<role>` (engine colour roles).
* **Joints**: `revolute` or `prismatic` about an axis in the part frame.
* **Drives**: `input` (scale on the input parameter; use a negative scale for
  counter-rotation), `follow`, `crankSlider`, `crankRod`.
* **Constraints**: `gearMesh` and `fixed`. The compiler checks modules,
  pressure angles, axes, centre distances and that each driven gear turns about
  its own centre. It phases every tooth so meshing gears interleave, then solves
  the linear velocity system. One input plus enough meshes and fixed parts must
  give a unique ratio for every gear joint, with `|ratio| <= 1000`
  (`constraint.ratio`).
* **Supported gear motion.** A gear's turn is its own revolute joint plus the
  joints of its parents, so these patterns work:
  * a gear on its own joint, or a gear without a joint on a turning parent whose
    axis passes through the gear centre (a pinion keyed to a driven shaft, or a
    compound gear riding on another gear);
  * a planet whose carrier is named in the mesh (`carrier`): the carrier must be
    a parent of at least one of the two gears; a gear outside a turning carrier
    must sit on the carrier axis; motion is measured relative to the carrier.

  Anything else is refused rather than solved wrongly:
  `constraint.gearMesh.parentRotates` (a turning parent whose axis misses the
  gear centre, for example a planet without its carrier named),
  `constraint.gearMesh.parentMoves` (a prismatic parent),
  `constraint.gearMesh.parentDrive` (a turning parent driven by `follow` or a
  crank, which is outside the linear solve) and `constraint.gearMesh.carrier`.
  After compiling, the compiler replays the posed assembly at five inputs and
  checks that every mesh keeps its axis, centre distance, tooth phase and tooth
  ratio (`constraint.gearMesh.motion`), so a compiled document always moves the
  way the solver assumed.
* **Gear shapes** are checked on the real sampled outline: a tooth needs a tip
  land (`part.gear.tip`, for example 8 teeth at 25 degrees with backlash 0.3),
  the outline must stay star-shaped (`part.gear.profile`), the bore and keyway
  corners must stay inside the root circle (`part.gear.bore`,
  `part.gear.keyway`), and the chamfer must be below half the width and leave
  inset cap loops that are star-shaped, separate and triangulate without
  overlap (`part.gear.chamfer`). A ring uses its own pressure angle for the
  same checks (`part.ringGear.teeth`, `.tip`, `.profile`, `.chamfer`). Without a
  `chamfer`, gears use 0.28 module (at most a quarter of the width) when that
  is valid, else half of it, else none.
* **Every gear mesh** is swept over one tooth pitch with the real outlines and
  refused when teeth overlap by more than 0.01 module
  (`constraint.gearMesh.interference`). This catches a ring with too few more
  teeth than its planet, a planet too small for its ring, and external pinions
  that undercut their wheel (small tooth counts or low pressure angles, for
  example 10 teeth against 36 at 14.5 degrees).
* **Known cost:** rings above about 300 teeth use a slower cap triangulation and
  may load in seconds; their chamfer falls back to none.
* **`repeat`** copies a part N times around an axis (`planet` → `planet1…3`).
  References to the base id expand to every copy; a repeated child of a repeated
  parent pairs by index.
* **Bounds** (`MGSolidLimits`): 64 KiB, 48 wire parts, 96 resolved parts,
  8 shapes per part, 256 profile points, 128 constraints, 16 steps, teeth
  8–200 (ring 20–400), module 0.2–20 mm, lengths up to 4 m. JSON nests at most
  64 levels (`MGLimits.depth`, arrays and objects on one path; the shipped models
  and built-in components use at most 12): a deeper document is `assembly.depth`, a
  deeper patch `patch.depth`, a deeper component definition `component.nesting`. The
  check runs first, without recursion (on `Data`, before the system parser). JSON
  `Data` must be UTF-8; other bytes (a raw NUL byte, as in UTF-16 or UTF-32 text, or
  invalid UTF-8) are refused as `json`.
* **Text limits**: `title` at most 80 characters (`assembly.title`), part `name`
  at most 60 (`part.name`), step `say` at most 240 (`step.say`). Keep a step to one
  or two short sentences.
* **Mesh budget**: at most 1,500,000 triangles and 1,000,000 vertices over all
  resolved parts (copies from `repeat` count), computed from the validated
  fields before any mesh is built (`MGShapeSpec.meshEstimate` gives the exact
  counts `mesh()` will produce); otherwise `assembly.budget`. At the limit the
  kernel meshes, the render meshes built while loading and the SceneKit buffers
  typically take about 200 MB (peaks can reach about twice that while
  normals are built), which recent iPhones and iPads hold. The planetary
  example uses 55,960 triangles (under 4%). A 256-point revolve (96 segments),
  8 per part, repeated 12 times (about 4.7 M triangles) is refused at once.
  In v2, step section cuts count toward the same budget (exact pre-pass counts, before
  any cut triangle is built).

**Patches.** `MGSolidParser.applying(_:to:)` accepts `params`, `parts` (merge
fields by id; `null` removes a field), `constraints`, `steps` and `title`. Part
ids stay stable and unchanged shapes keep their meshes, so a what-if (hold the
carrier, free the ring) recompiles the kinematics without rebuilding geometry.
`MGSolidRenderer.setAssembly(_:)` likewise keeps nodes whose mesh did not change;
a material-only change restyles the node in place. A section cut gives each cut
part a private material copy, so parts that share a preset are never cut with it.

## Assembly v2: facts, placeholders and truth tiers

`"v": 2` is a strict superset of v1. A v1 document keeps its exact meaning: the same
input gives the same document, the same refusals, and its text is never filled. The new
keys are legal only in v2; in a v1 document they are refused with the usual reason
(`part.unknown.expect`, `step.unknown.check`, `assembly.unknown.annotations`). Keys in v2 so
far: top-level `annotations`; part `expect`, `offAxis`, `opacity` and `emissive`; step `check`,
`unchecked`, `section`, `ghost` and `annotate`.
Later features add their keys to the v2 sets in `MGSolidFormat`.

### Facts

The engine keeps every number it can stand behind in a facts table
(`MGSolidDocument.facts`; `fact(_:)` looks a name up and resolves anchors). Each fact has a
value, a unit, a tier and a source.

| Name | Value | Unit |
| --- | --- | --- |
| `<part>.teeth`, `<part>.module` | gear and ring parts | –, mm |
| `<part>.speed` | revolute part with a linear drive (`input`, `follow` or a gear-mesh solve): joint turns per input turn, **relative to its parent**, signed about its own joint axis | – |
| `<part>.worldSpeed` | the same part's turns per input turn **in the world frame**: its own rate plus every turning revolute ancestor, when all their axes are parallel to its own (otherwise there is no such fact). A planet on a carrier: `speed` −20/21 relative to the carrier, `worldSpeed` 2/7 − 20/21 = −2/3. | – |
| `<part>.travel` | driven prismatic part: largest minus smallest displacement over one input turn (720 samples, ends included); the stroke of a slider-crank | mm |
| `<part>.crankRadius`, `<part>.rodLength` | part with a `crankSlider` drive | mm |
| `count.<base>` | copies made by `repeat` (`count.stage.planet`) | – |
| `<base>.<name>` | a fact every copy shares (`stage.planet.teeth`) | as the copies |
| `<instance>.ratio` | component output anchor speed / input anchor speed (`stage.ratio`) | – |
| `dim.<id>` | a [dimension](#annotations-v2) the engine measured | mm or ° |

Component anchors resolve: `stage.output.speed` is `stage.carrier.speed`. A fact's text never
shows a non-zero value as "0" (a 1:1000 train shows "-0.001"). Tooth counts,
modules, crank sizes and counts are Solved. A speed or travel takes the tier of its drive
chain (see tiers below): the input at ±1 turn per input turn and everything the engine
solves from it are Solved; an `input` scale other than ±1 or 0 and every `follow` ratio
are numbers the author set, so they and every speed computed from them are Built.

### Placeholders

In v2, the `title` and every step `say` may hold `{name}` or `{name|mod|…}` (up to three
modifiers). The engine fills them with `MGPhysics.format` (about three significant figures)
and keeps the authored text in `MGSolidStep.template`. Modifiers:

* `abs` drops the sign. It needs a `check` in the same step that proves the sign of that
  fact with a strict inequality (`lt` t with t ≤ 0, or `gt` t with t ≥ 0; an `eq` never
  proves a sign, because −0.001 and +0.001 both show as "0"), otherwise
  `text.sign.<name>`; a title cannot use it. So "the other way" in the caption is
  proved, not typed.
* `inv` (1/x) and `frac` (the exact fraction p/q with q ≤ 100 000 within a relative
  10⁻¹², for example "2/7"; π has none) need a pure number (no unit).
* `pct` (× 100, "%") and `deg` (turns × 360, "°") apply to speeds and ratios only.
* `pct`, `deg` and `frac` end a chain.

```json
{"say": "The carrier turns {stage.output.speed|frac} of a turn.", "check": [{"value": "stage.output.speed", "lt": 1}]}
```

gives "The carrier turns 2/7 of a turn." for a 24-tooth sun and a 60-tooth ring
(`{stage.output.speed}` gives "0.29", `{stage.output.speed|inv}` "3.5"). Refusals:
`text.placeholder.<name>` (no such fact), `text.placeholder` (bad grammar: names are ASCII
letters, digits, `_` and `.`, at most 64 characters; modifiers are one of the five words),
`text.brace`, `text.modifier.<mod>` (unknown), `text.modifier.<mod>.<name>` (does not
apply, for example `inv` of a value in mm, `deg` of a tooth count, or `frac` of π),
`text.sign.<name>`, `text.rounding.<name>`: a non-zero value that would print as "0"
(a 1:300 reduction is 0.0033); use `frac` or `inv` for it, and `text.range.<name>`: a
modifier step whose result is not a finite, normal number (`inv` of 1e-309 overflows; it
is refused there, so a second `inv` cannot turn it into a false "0").

**Rule N1 (numbers).** In a v2 caption, every number character must come from a
placeholder; otherwise `text.number.step.<n>` (1-based). Every Unicode scalar counts, by
the toolchain's Unicode properties and a pinned Unicode 18.0.0 Numeric_Type table (2,348
scalars, `MGSolidNumericScalars`), so a number newer than the runtime's data counts too: ASCII
and other digits, "½", superscripts ("mm²", "CO₂") and a digit joined to a letter. The
exception is a step marked `"unchecked": "<why>"` (1–60 characters): it may type numbers,
and it shows the "Not checked" chip. For units and formulas write "square mm" or mark the
step `unchecked`. So "Its stroke is 36 mm." is refused; "Its stroke is
{engine.piston.travel}." shows "Its stroke is 36 mm." with its numbers Solved.
N1 covers number characters only. It does not see number words ("three times slower"),
and it cannot tell whether a placeholder names the right fact: "{count.stage.planet}
times slower" prints "3 times slower" from the planet count. A `check` is the only proof of
a relation, and the check report lists which fact filled each placeholder (`stepFacts`).
Titles and part names may type digits ("V8 engine"), but a title with a typed number is
Described.

**Claim checks.** A step may state up to 8 claims that the engine proves before it accepts
the document: `{"value": "<fact>", "eq" | "lt" | "gt": x, "tol"?: t}`, the same shape and
meaning as the lesson `check`. Without `tol`, `eq` compares what the learner sees
(`MGPhysics.format` of both numbers), except that a target of 0 needs exactly 0; with
`tol`, |value − x| ≤ t. Refusals: `check.failed.<name>` (the claim is false),
`check.fact.<name>` (no such fact; the two prefixes never collide, even for a part named
`fact` or `failed`), `check.comparison`, `check.tol` (only with `eq`),
`check.value`, `check.object`, `step.check` (not a list of 1–8), and the key reasons
`step.check.missing.value` and `step.check.unknown.<key>`.

### Truth tiers

The engine computes a tier for every visible claim. An author never sets one: a key named
`tier` anywhere in a v2 document is refused (`tier.key`), at the top level and inside
`with` too (so a component parameter cannot be called `tier` in a v2 document).

| Tier | Chip | Meaning |
| --- | --- | --- |
| Solved | "Solved" (motion), "Numbers solved" (caption, title), "Checked" (check) | The engine computed it from the reference input (±1) and every check passed: a gear speed from the mesh solve, a crank drive, a measured travel, a tooth count. |
| Built | "Schematic motion" / "Schematic" | Exact geometry from the author's numbers, behaviour from the author: an `input` scale other than ±1, a `follow` ratio, and everything computed from them (scripted motion, stand-ins and cited sizes come in later releases). |
| Described | "Not checked" | Text the engine does not check: a caption marked `unchecked`, a title with a typed number, or a v1 caption or title with a number in it. |

* **Motion** of a part with its own moving joint: the lowest tier over its drive chain
  (a `follow` source, a crank, the inputs of its gear-mesh solve) and every moving
  ancestor. A static part, an idle joint and a part that only rides on a moving parent
  make no motion claim.
* **Captions and the title**: Described when `unchecked` or when they type a number;
  otherwise the lowest tier of the facts they show. A caption that shows no engine number
  gets **no tier** and no check mark, even with checks: the engine cannot tell what its
  words claim. The tier covers the numbers, not the words ("Numbers solved").
* **Checks** are claims of their own (`step.<n>.check.<k>`, chip "Checked"), with the
  expression as text, for example "Checked: stage.sun.teeth > 0".
* `MGSolidDocument.claims` lists the claims (motion once per authored part, then the
  [annotations](#annotations-v2), then the title, then each caption and its checks), each with its chip text and a reason;
  `legend` gives the counts and one line ("Solved 8 · Not checked 1", always shown),
  "Some motion is schematic" when a motion claim is below Solved, and "Shapes as
  authored". `describe(id)` returns one part's motion, tier, facts and what its motion
  source does not check, for example
  `{"id": "stage.carrier", "motion": "Solved by gearMesh (0.29 turns per input turn)", "notChecked": ["3D tooth contact", …]}`;
  a part on a turning parent says "relative to <parent>" and gives its world speed.

## Sections, ghosts and part appearance (v2)

A casing hides the mechanism inside it. In v2 a step can cut parts open or show them
see-through, and a part can be faint or give off light.

```json
{"say": "Cut the front half of the casing away.", "section": {"normal": [0, -1, 0], "offset": 0, "parts": ["casing"]}},
{"say": "Seen through the casing.", "ghost": ["casing"]}
```

* **`section`** cuts the listed `parts` (1–16 ids; a `repeat` base cuts every copy) with
  a plane in assembly coordinates (Z up, mm): points with `normal · p > offset` are cut
  away (`offset` defaults to 0). So the normal points from the kept half toward the
  removed half: to open the side that the default cameras look at, use `[0, -1, 0]`.
  The cut is a true section: the engine cuts each closed shell of the part, chains the
  open edges into loops and fills them with flat cap faces (`MGSolidSection.cut`), so a
  cut part is still a closed, outward mesh with solid cut walls. Each hole goes to the
  smallest outer loop that contains it (a pulley rim and its hub, a double-wall cup); a
  loop that touches itself or a hole that touches its outer wall at one vertex (a plane
  through a tube's inner rim) is split or joined at that vertex; a cavity (an inverted
  inner shell) is a hole of the shell around it. The compiler checks every cut it builds
  (`MGSectionCut.isSound`: a valid cap range, closed, outward, cap triangle areas that add
  up to the cap area within 1e-6 × max(1, area)) and refuses one that fails
  (`section.open.<id>`). This is a consistency check, not a proof: it does not test that
  cap vertices lie on the plane or that every shell is outward, and far below 1 mm² its
  tolerance can miss a folded cap. Other parts are not
  touched. The plane is placed at the document's default input (`params.input`) with
  explode 0; a cut part then keeps its cut as it moves and explodes, like a physical
  cutaway model. Use sections on still parts (casings, housings, walls) for the
  clearest view. A step without `section` shows nothing cut.
* **Refusals**: `step.section`, `step.section.missing.<keys>`,
  `step.section.unknown.<keys>`, `step.section.normal` (zero or not three numbers),
  `step.section.offset`, `step.section.parts`, `ref.unknown.<id>`, and per part
  `section.miss.<id>` (the plane removes nothing of it) and `section.empty.<id>` (the
  plane removes all of it). `section.loops.<id>` and `section.nesting.<id>` mean the
  part's mesh is not a clean closed solid (open, or self-intersecting); `section.mesh` is
  the same for a mesh built in code with bad indices or numbers. Called directly,
  `MGSolidSection.cut` and `estimate` also refuse a plane that removes nothing or
  everything (`section.miss`, `section.empty`; `crossing` tells first).
* **Cost**: a pre-pass counts every distinct cut exactly (`MGSolidSection.estimate`)
  before any cut triangle is built, and the cuts count toward the document's mesh
  budget with the parts (`assembly.budget`). Each distinct part and plane reads its
  part's mesh once, and all distinct cuts of one document may read at most 400,000 part
  triangles (`section.budget`, checked before each cut is classified). The cap work is
  budgeted too: grouping loop points, the hole-to-outer search (outer loops walked by area
  with a box test and one point-in-polygon test per candidate), hole bridges and splices
  may charge at most 4,000,000 units over all cuts (`section.budget`), before any cap is
  built. Caps use the zipper strip or an ear clipper that tests only reflex vertices
  through a grid; that is fast on gear, ring, comb and spiral loops but has no proven
  linear bound. These are **measured benchmarks**, not a proven worst case
  (`marty-solid check`, release build, Apple M1, best of three): seven face cuts of a
  200-tooth gear 0.65 s; one cut of eight 63-fin concentric "labyrinth" revolves in one
  part (391,680 triangles read, 585,216 cut triangles) 1.08 s, of which 0.17 s builds the
  part; the full turbofan casings cut by one plane 0.13 s; the idler example 0.03 s. On
  these the cut cost grows linearly, about 2.3 µs per part triangle read. Over-budget
  documents in these sets are refused in 0.08–0.17 s. **Deliberate limit**: the budget
  allows about 13 distinct planes on a 120-tooth ring (28,800 triangles each; 14 are
  refused), 8 on a 200-tooth ring and 7 on a 200-tooth gear; one plane shared by many
  steps is charged once. Steps that share a plane
  share one cut; a patch that keeps a part's shape and place reuses its cut.
* **`ghost`** lists parts (1–16 ids) that the step shows see-through, at opacity
  `MGSolidView.ghostOpacity` (0.2), so the parts behind them show. Ghosts cast no
  shadow.
* **Part `opacity`** (0.1–1, default 1; `part.opacity`) makes a part faint in every
  step, for a glass body or a casing that should always show what is inside. A ghost
  never makes a part more opaque than its own `opacity`.
* **Part `emissive`** `{"role": "<colour role>", "intensity": 0–4}` (intensity default 1)
  makes a part give off light in an engine colour role (a hot core, an indicator lamp).
  Refusals: `part.emissive` (intensity out of range, or not an object),
  `part.emissive.role`, `part.emissive.missing.role`, `part.emissive.unknown.<keys>`.
* Sections, ghosts, opacity and light change what the learner sees, not what the engine
  claims: they add no tier and no fact.

`MGSolidDocument.view(step:)` gives what a step shows (per part: the cut, the opacity
and the light, and the ids of the annotations it shows; `nil` gives the plain scene). `MGSolidRenderer.show(_:)` displays a view:
cut parts swap in their capped geometry (built once and kept), ghosts blend over the
parts behind them, and emissive parts glow with the camera's bloom.
`MGSolidSnapshot.make(_:step:params:)` exports a view as snapshot format v2 (below).
`marty-solid check` lists every step section (parts, cap triangles, cap loops, closed),
and `marty-solid render` shows each step with its section and ghosts.

## Annotations (v2)

A v2 assembly can label parts, draw arrows and show measured dimensions. The engine computes every
annotation from the posed model. An author never types a measured value, a motion direction or a
turn sense: the engine finds them, and refuses a stated direction or sense that is wrong.

```json
"annotations": {
 "labels": [{"id": "lSun", "at": {"part": "stage.sun", "offset": [0, 0, 14]}, "text": "Sun: {stage.sun.teeth} teeth"}],
 "arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w", "sense": "cw"},
            {"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}, "expect": [-1, 0, 0]},
            {"id": "aG", "meaning": "force", "cause": "gravity", "from": "mass", "to": {"part": "mass", "offset": [0, 0, -30]}, "text": "Weight"},
            {"id": "aAir", "meaning": "flow", "from": {"world": [0, -80, 40]}, "to": {"world": [0, 80, 40]}, "text": "Air in"},
            {"id": "aLook", "meaning": "pointer", "from": {"world": [60, 0, 90]}, "to": "valve", "text": "Inlet valve"}],
 "dimensions": [{"id": "gap", "a": "p", "b": "w"},
                {"id": "stroke", "a": {"part": "piston", "point": "centre"}, "b": {"world": [0, 0, 0]}, "along": "x", "over": "input"},
                {"id": "tilt", "kind": "angle", "a": {"world": [100, 0, 0]}, "vertex": "pivot", "b": {"part": "arm", "offset": [80, 0, 0]}}]}
```

The keys `labels`, `arrows` and `dimensions` are closed (`annotations.unknown.<keys>`,
`annotations.object`). Annotation ids are plain identifiers (`label.id`, `arrow.id`,
`dimension.id`). They join the document's one namespace: an id equal to a part, copy, `repeat`
base, instance or anchor name, or to another annotation, is `id.duplicate.<id>`. A refusal of one
annotation names its id in `MGSolidIssue.part`.

### Anchors

| Form | Meaning |
| --- | --- |
| `"p"` | the origin of part `p`'s frame (for a gear or shaft: a point on its axis) |
| `{"part": "p", "offset": [x, y, z]}` | a point in `p`'s frame, mm, each coordinate within ±4000 |
| `{"part": "p", "point": "centre"}` | the centre of `p`'s mesh bounds, in its frame |
| `{"world": [x, y, z]}` | a fixed world point (kernel frame: Z up, mm) |

A part anchor moves with its part in every pose: an offset away from the joint axis turns with the
part, so put a label on the axis when the part spins. A part id, a `repeat` copy id and an anchor
name (`stage.output`) are accepted. A base id with copies and an instance id name more than one part
(`anchor.ambiguous.<id>`); an unknown id is `anchor.ref.<id>`. Bad shapes: `anchor.form`,
`anchor.offset`, `anchor.point`, `anchor.world`.

### Text and tiers

Label, arrow and dimension text follows the v2 caption rules: placeholders with the modifiers
`inv`, `frac`, `pct` and `deg`, and rule N1 (`text.number.label.<id>`, `text.number.arrow.<id>`,
`text.number.dimension.<id>`). `abs` is refused (`text.sign.<name>`): no step proves a sign for an
annotation. Filled text is 1–40 Unicode scalars, authored text at most 160 (`label.text.<id>`,
`arrow.text.<id>`, `dimension.text.form.<id>`). A label or arrow may carry `"unchecked": "<why>"`
(1–60, `label.unchecked.<id>`, `arrow.unchecked.<id>`; an arrow needs `text` for it,
`arrow.unchecked.text.<id>`): its text may
then type numbers and its claim is Described.

Annotation claims (kind `annotation`, id = the annotation id) come after the motion claims, in
authored order: labels, arrows, dimensions. The legend counts them. When any non-pointer arrow has no
fact length, the legend adds the note "Arrow lengths are not to scale" (`MGSolidLegend.notes`).

| Annotation | Claim tier |
| --- | --- |
| label | Described with `unchecked`; else the lowest tier of the facts it shows; no claim when it shows none |
| motion arrow (`turn` or `line`) | the motion tier of its part's chain; with a fact `length`, also no higher than that fact |
| force arrow with `"cause": "gravity"` | Solved (its direction is checked) |
| force arrow without `cause`, flow arrow | Described: direction and length as authored |
| pointer arrow | no claim (only its text, when the text shows facts) |
| dimension | Solved; with `over`, or at a `params.input` other than 0, the lowest motion tier of its anchors' chains |

An arrow's text lowers its claim to the text's tier (an `unchecked` text makes it Described).

### Labels

`{"id", "at", "text", "unchecked"?}` (`label.missing.<keys>`, `label.unknown.<keys>`,
`label.object`). The text shows at the anchor (see Placement).

### Arrows

`id` and `meaning` are required (`arrow.missing.<keys>`, `arrow.unknown.<keys>`,
`arrow.meaning.<id>`). A key that the meaning does not take is `arrow.key.<key>.<id>`. Common keys:
`text`, `unchecked`.

| Meaning | Keys | Direction | Checks |
| --- | --- | --- | --- |
| `motion`, `"style": "turn"` | `on` (a part id string, `arrow.on.<id>`), `sense` (`cw` or `ccw`, optional) | The engine: the sign of the part's composed world turn rate (`<part>.worldSpeed`). Drawn as a 270° arc around the joint axis. | `arrow.turn.joint.<id>` (not a revolute part), `arrow.still.<id>` (its own joint never turns; a part that only rides a turning parent counts as still), `annotation.motion.nonlinear.<id>` (a crank drive in its chain), `arrow.turn.steady.<id>` (a turning joint above it with a non-parallel axis, so there is no single world rate), `arrow.sense.<id>` (the stated sense is wrong; "cw" and "ccw" as seen from the tip of the joint axis), `arrow.sense.form.<id>` |
| `motion`, `"style": "line"` (the default) | `from` (a part anchor), `expect` (a world direction, optional), `length` (optional) | The engine: the anchor's exact velocity at the default input, from its linear motion chain. | `arrow.from.<id>` (a world anchor), `annotation.motion.nonlinear.<id>` (a crank drive in its chain), `arrow.still.<id>` (no velocity at the default input), `arrow.expect.<id>` (more than 30° from the engine direction, sign included), `arrow.expect.form.<id>`, `arrow.style.<id>` |
| `force` | `from`, `to`, `cause` (`"gravity"`, optional) | As authored. With `cause`, it must be within 10° of world −Z at the default input. | `arrow.gravity.<id>`, `arrow.cause.<id>` |
| `flow`, `pointer` | `from`, `to` | As authored. | — |

Force, flow and pointer arrows shorter than 0.5 mm at the default input are `arrow.length.<id>`.
A motion line arrow's `length` is a number in mm (10–4000) or `{"fact": "<name>", "scale": s}` (mm per
unit, 0.001–1000): its length is then |fact| × s, clamped to 5–4000 mm, and the arrow claims a
magnitude (`arrow.length.form.<id>`, `arrow.length.fact.<id>` for an unknown fact). The default length
is 15 % of the model's bounding diagonal at the default input.

While a view plays, a motion line arrow follows the exact velocity at each pose; it hides while its anchor has no
velocity. A turn arrow rides
the frame its part turns in (the parent frame), so it does not spin with the part.

Appearance (the same in every renderer): shaft radius 0.6 % of the bounding diagonal, head 4 shaft
radii long and 2.5 wide. Colour roles: force `warn`, flow `accent`, motion `good`, pointer `ink` (the
theme's ink colour, the `white` role); dimension lines are `ink`. Arrows and dimension lines are not
cut, not ghosted and cast no shadow.

### Dimensions

`{"id", "a", "b", "kind"?, "vertex"?, "along"?, "over"?, "text"?}` (`dimension.missing.<keys>`,
`dimension.unknown.<keys>`, `dimension.object`).

* `kind` is `distance` (the default) or `angle` (`dimension.kind.<id>`).
* A distance is |b − a| in mm. With `"along": "x"`, `"y"` or `"z"` it is the absolute world component on
  that axis (`dimension.along.<id>`, also for an angle).
* An angle is the angle at `vertex` between `a` and `b`, 0–180°. `vertex` is required for an angle and
  refused for a distance (`dimension.vertex.<id>`).
* The value is measured at the default input (`params.input`) with explode 0. With `"over": "input"` it is
  the largest minus the smallest value over one input turn (input 0 to 2π), computed exactly from the joint's
  closed form, not sampled. `over` needs an anchor that moves (`dimension.over.<id>`; any other value is
  `dimension.over.form.<id>`). The engine has the exact range only for a distance (optionally `along` an axis)
  whose one moving anchor moves by one prismatic joint with a linear drive or a crank-slider, while the other
  anchor stays where it is (a world point, or a point on a turning axis); anything else is
  `dimension.over.motion.<id>`. The stroke of a slider-crank is such a range.
* A distance below 0.01 mm at the default input, or an angle arm below 0.01 mm, is `dimension.zero.<id>`. With
  `over`, a range below 0.01 mm is `dimension.over.still.<id>`.
* The value is the fact `dim.<id>` (unit `mm` or `°`, source `dimension`). Captions, labels, arrow text and
  checks can show and check it. A fact with that name already (a part named `dim`) is
  `dimension.fact.<id>`. No key sets the value.
* `text` defaults to `{dim.<id>}`. Given text must show `{dim.<id>}` (`dimension.text.<id>`) and follows N1
  with no `unchecked`.

Drawing: a line between the posed anchors with an end tick at each end; with `along`, the line runs
parallel to the axis, offset by 5 % of the bounding diagonal, with two extension lines; an angle draws
its two arms and an arc at the vertex.

### Poses: every claim holds at every pose its view can show

The checks above run at the default input (`params.input`) with explode 0. Then the engine decides, for every
view, whether each claim it shows holds at every pose the view can show. A step shows its `spin` range (the
default input to the default input + `spin` turns) at its explode value (the step's `explode`, else
`params.explode`). The plain view shows the default pose at `params.explode`. The rules are exact; nothing is
sampled. They use which joints move during the view.

**The linear-motion rule.** A motion line arrow, a turn arrow, an `expect`, and any dimension shown in a step with
`spin` are allowed only where every moving joint above the annotated point is linear in the input with a constant
rate: `input` drives, `follow` with a constant ratio of such a joint, gear meshes and planetary carriers. A chain with
a crank-slider or crank-rod drive, or a `follow` of one, reverses or changes speed, so it is refused with one
reason, `annotation.motion.nonlinear.<id>`. Show such motion in a step without `spin` (labels, still dimensions and
`over` ranges work there), or put a turn arrow on a steady part. A turn arrow's sense is the sign of the composed
world turn rate about its axis (`<part>.worldSpeed`): one constant for a linear chain with parallel axes.

* An anchor is **world-fixed** when every moving joint above it is a revolute whose axis passes through it (a
  point on a turning shaft's axis), or when nothing above it moves.
* A **shown dimension** without `over` must be constant: the step has no `spin`, or all its anchors are
  world-fixed, or all of them ride the same moving joints (a rigid body; with `along`, those joints must not
  turn, because a turn changes the world components). Its value at the view's first pose must equal its
  fact. With `over`, its exact range at the view's explode value must equal its fact.
* **Shown text** (a label, an arrow or dimension text, the step caption, the title) may display a `dim.<id>` fact
  only when that dimension meets the same rule in the view (also when the dimension itself is not shown).
* A **gravity arrow** must not turn: in a step with `spin`, both its anchors are world-fixed or translate together.
  It must point within 10° of −Z at the view's first pose.
* A **motion line arrow** must not ride a turning joint in a step with `spin` (use a turn arrow there); its linear
  chain then moves it at one constant velocity. A stated `expect` must hold at the view's first pose.
* A **turn arrow** with a stated `sense` must not be in a step with a negative `spin`: turn senses are exactly
  constant for the steady parts a turn arrow allows.

A failure is `annotation.pose.<id>`; a caption is `text.pose.step.<n>`, the title `text.pose.title`. A step with a
negative `spin` plays the input backwards (`MGSolidView.motionSense` is −1): turn arcs and motion arrows draw the
motion that the view shows. Labels and the other arrows ride their parts and claim no direction.

**One gate for every output.** `MGSolidDocument.checkedAnnotations(_:params:)` gives the annotations a renderer may
draw for a view at a pose, or nil. A compiled document and its views are read-only to hosts: every stored property
of `MGSolidDocument`, `MGSolidStep`, `MGSolidGear`, `MGSolidFact`, `MGSolidStepSection` and `MGSolidView` (its parts
and cuts, section, annotation list, playback sense, step and fingerprint) has an internal setter, so the only way to
change a document is the parser or a patch, which compiles and checks it again, and the only way to get a view is
`view(step:)`. The view must carry this document's fingerprint (a SHA-256 identity computed when the document
compiles) and list exactly the annotations its step shows; a host hides annotations with the renderer switch
`MGSolidRenderer.annotationsHidden`, which never changes what the engine checked. The pose must be exactly one the view
shows, with no tolerance: the step's explode value, and for a still step exactly the default input; for a step with
`spin`, an input from the default input to `defaults.input + spin * 2 * .pi` (the render plan uses the same
expression). A document with annotations keeps its default input within 10,000 turns (`annotations.input`), so pose
arithmetic stays precise. The raw piece builder is internal. `MGSolidAnnotations.frame` (then `refusal: .unchecked`, no
placements), `MGSolidRenderer` (pieces hidden) and `MGSolidSnapshot.make` (no `annotations`) all use it, so a
view or pose that the engine did not check shows no annotations. `marty-solid render` also draws annotations on
`hero.png` and the step stills only (`MGSolidShot.showsAnnotations`), not on `exploded.png` or the loop frames.

### Visibility

* When no step has `annotate`, every annotation shows in every step and in the plain view. Then there
  may be at most 12 (`annotations.visible`).
* When any step has `annotate`, each step shows exactly its list (0–12 ids: `step.annotate`,
  `step.annotate.count`, `step.annotate.ref.<id>`). A step without the key shows none, and the plain view
  shows none. An annotation that no step shows is the warning `annotation.unused.<id>` (strict refuses).
* `MGSolidDocument.visibleAnnotations(step:)` and `view(step:).annotations` give the ids.

### Limits

| Limit | Value | Reason |
| --- | --- | --- |
| Labels, arrows, dimensions per document | 32, 32, 16 (`MGSolidAnnotationLimits`) | `labels.count`, `arrows.count`, `dimensions.count` |
| Visible at once | 12 | `annotations.visible`, `step.annotate.count` |
| Text | 1–40 scalars filled, 160 authored; `unchecked` 1–60 | as above |
| Occlusion ray tests | 2,000,000 triangle tests per frame | over it, `occluded` is null and the anchor is drawn as visible |

Arrow and dimension pieces join the mesh budget with exact counts before any mesh is built: a line
arrow is 48 triangles, a turn arrow 784, a distance 96 (160 with `along`), an angle 832
(`assembly.budget`).

### Placement

`MGAnnotationLayout.place(_:)` is one pure function. The SwiftUI overlay, `marty-solid render` and the
snapshot call it through `MGSolidAnnotations.frame(document:view:params:camera:…)`.

1. A core perspective projection of `MGSolidCamera` (`MGAnnotationProjection`, the same as
   `MGSolidRenderer.project`).
2. Text box: font f = clamp(round(0.022 × view height), 11, 20) px; box width 0.58 × f × scalars + 12 px,
   height 1.3 × f + 8 px. Renderers shrink their font until the real text fits the box (`MGSolidOverlay.fit`).
3. Safe frame: the view inset by 12 px, minus the bottom 20 % when a caption shows, minus a top band of
   14 % when the host draws a title (the CLI does); the top-right legend corner (30 % × 10 %) is excluded.
4. Candidates: 8 directions at 24, 48 and 72 px. The first points away from the projected model centre
   (for arrow and dimension text: perpendicular to the line, away from the centre). Clockwise, then outward.
5. A candidate is valid only inside the safe frame, 4 px away from every placed box, off every label
   anchor dot (6 px), with a leader at most 30 % of the view diagonal.
6. Score: overlap with highlighted parts' screen boxes + 0.5 × leader length + 1000 × leader crossings;
   ties go to the earlier candidate.
7. Order: labels (in `annotate` or authored order), then arrow texts at arrow midpoints, then dimension
   texts at line midpoints. Arrows without text place nothing.
8. A text with no valid candidate becomes a numbered marker at its anchor; its text goes to the callout
   list (bottom left of the safe frame, in order). An anchor outside the view goes there with "(off view)".
   Nothing is dropped and no box overlaps another.
9. Stability: a text keeps its previous candidate while that stays valid. Pass the previous frame each
   time; live views re-place at most every 100 ms.

Each record (`MGAnnotationPlacement`) holds `id`, `kind`, `text`, `box`, `leader`, `anchor` (normalised view
coordinates, origin top left), `occluded` (true, false or null), `callout`, `candidate` and `offView`.
`MGAnnotationFrame` adds the view size, the font size and the posed anchor points; a clip export will
carry one per frame. `marty-solid check` reports `annotations` (id, kind, meaning, tier, text, value,
`anchorsWorld`, `occludedAtDefaultCamera`) and `placements` (the placement of the plain view and of each
step that shows annotations, at the view's first pose (the default input at the view's explode value) and the
snapshot's default camera, aspect 16:10), so a model can see which texts fell into the callout list. `placements` is not the layout of the
rendered stills: those use the end of each step's spin range, the step's explode value and its camera
preset. A frame lays out nothing, and says why in `refusal`, for a view or pose the engine did not check
(`.unchecked`) or a view size that is not finite and positive (`.viewSize`); nothing is dropped silently.

### Occlusion and renderers

* The core casts a ray from the camera to each text anchor against the posed meshes (cut meshes for cut
  parts). Parts shown below opacity 0.5 (ghosts, faint parts) do not block it. Part bounds are tested
  first. A blocked anchor draws a hollow dot and a dashed leader; its text still shows.
* `MGSolidRenderer` draws annotations only for the document it was loaded with (`init(document:)` or
  `setDocument(_:)`; the renderer keeps that document's fingerprint) and only through `show(document:view:)`. An
  assembly given on its own (`init(assembly:)`, `setAssembly(_:)`) and `show(_:)` show none, so a renderer can never
  draw one document's annotations beside another assembly's motion. It builds one node per arrow or dimension piece
  (one unit cylinder and one unit cone, scaled); `apply(_:)` moves them and geometry is never rebuilt. Loading a
  document moves the parts to its default pose, and `show(document:view:)` poses every part before the annotations
  attach, in one SceneKit transaction, so they never show beside parts in another pose.
  `highlightAnnotations(_:)` brightens some; `annotationsHidden` hides them all.
* `MGSolidOverlayView` (SwiftUI) and `MGSolidOverlay.draw` (CoreGraphics, used by `marty-solid render`) draw
  labels, leaders, dots, chips (a bar in the tier colour: good, warn, muted), callouts and the legend from
  one frame record.
* The snapshot `/2` carries the step's annotations (see Snapshot below). The path tracer bridge gets the
  arrow and dimension triangles as ordinary triangles; it draws no text.

### Not checked

* Words: annotation text is checked for numbers only, not for meaning.
* Force and flow arrows other than the gravity direction; every arrow length without a fact.
* The rules are conservative: some constant claims are refused (two anchors on different parts that happen to
  keep their distance). Move such a claim to a step without `spin`.
* Occlusion along leader lines (only the anchor point is tested).
* Placement uses an estimated text width; very long words get small.

## Warnings, strict mode and the check report

The compiler lints every document, v1 and v2, after it compiles
(`MGSolidDocument.warnings`, in part order; a `repeat` copy reports its base id once).
The plain API only warns. The strict profile (`MGSolidParser.document(…, profile: .strict)`,
`MGSolidParser.applying(…, profile: .strict)`, `marty-solid check --strict`; the default for
model harnesses) refuses only what the document itself shows to be wrong: a jointed part that
nothing moves, a turn axis that misses its own jointed part, and an annotation that no step shows. The child-frame warnings
are heuristics and stay warnings in every profile; the read-back below is how an author
checks frames.

| Warning | When | Strict |
| --- | --- | --- |
| `joint.idle.<id>` | A part has a `revolute` or `prismatic` joint but no drive and no constraint moves it, so it never moves. Add a drive (`{"input": 1}`), a mesh or a `fixed` constraint, or remove the joint. | refused |
| `frame.child.absolute.<id>` | The double offset, confirmed by geometry with every joint at 0: the child's bounds miss its parent's bounds as placed, but if its `at` / `rot` are read as world values it lies nearer, within one parent size. A child that touches its parent as placed (arm links, equal-link chains, stacked plates) never warns, and neither does a child of a parent at the world origin (only rotation differs there). Correct layouts can still warn (spaced plates, a plate on posts). | warning |
| `frame.axis.off.<id>` | A revolute part's axis line misses its own mesh bounds. Mark a part that turns about an outside axis on purpose with `"offAxis": true`; this key needs v2, so a v1 document with such a part fails strict mode until it moves to v2. | refused |
| `frame.child.far.<id>` | A child's bounds miss its parent's bounds grown by 1.5 times the parent's largest size. Often the same error; sometimes intended. | warning |
| `annotation.unused.<id>` | Some step uses `annotate`, but no step lists this annotation, so the learner never sees it. | refused |
| `annotation.cut.<id>` | A part anchor of an annotation that a step shows lies in the half that the same step's `section` removes from that part, so the annotation floats over the cut. | warning |

`expect` mismatches (`expect.axis.<id>`, `expect.up.<id>`) are refusals in every profile.

`marty-solid check [--strict] FILE.json` prints, besides `ok`, `reason`, meshes and gear
checks, `engine`, `partTiers` and `motionTiers` (below): `version`, `warnings`, `facts` (value, unit, text, tier, source), `legend`
(counts, text, claims; with annotations also `notes`), `stepTiers`, `stepFacts` (for each step, the fact behind each
placeholder in order, and each check with its `value`, `comparison`, exact `target`,
`tolerance` and text), `notChecked` per motion source, and a
plain-words `readBack` of every part at input 0. One line per part gives its world centre
and size (from its vertices), how it moves (axis words such as "a horizontal axis (+X)",
speed, tier and source), its parent and its `at` in the parent frame, how far its origin is
from a turning parent's axis, and where its local +Z points:

```
tower: world centre (0, 0, 45) mm, size 8 x 8 x 90 mm; static; root (at [0, 0, 0] in the world frame); local +Z points +Z
rotor: world centre (0, 0, 92) mm, size 20 x 10 x 10 mm; turns about a horizontal axis (+X) through (0, 0, 92); 1 turn per input turn (Solved, input); child of tower (at [0, 0, 92] in the tower frame); local +Z points +X
blade: world centre (0, 30, 92) mm, size 2 x 60 x 4 mm; fixed to its parent, moves with rotor; child of rotor (at [0, 30, 0] in the rotor frame); its origin is 30 mm from the rotor axis; local +Z points +X
```

A model cannot see the render, so this is its repair loop: compare the read-back with the
intent, fix, check again.

### The report as a library API

The report is built by the library, so `marty-solid` and any host (an MCP server, a data
pipeline) print the same JSON from one implementation:

* `MGSolidReport.check(data:library:profile:engine:)` parses and checks document bytes,
  exactly as `marty-solid check` does. Bytes over 64 KiB get the short refusal
  `{"ok": false, "reason": "assembly.bytes", "part": null}` before they are parsed or hashed;
  a refused document gets `ok`, `reason`, `part`, `strict` and `file`.
* `MGSolidReport.make(_:profile:source:engine:)` reports on a compiled document (compile it
  with the standard profile, so the report can show what `.strict` refuses).
* `MGSolidReport.refused(_:profile:source:engine:)` gives the refusal shape.
* Every entry point first checks the host's `engine` value, with one walk that does not
  recurse: a non-finite number, more than 8 levels (`engineDepth`) or more than 4,096
  bytes (`engineBytes`) gives the refusal `report.engine`, which carries no engine.
  `MGSolidReport.text(_:)` measures a value before it converts or encodes it, and gives
  `{"ok": false, "reason": "report.encoding"}` for a non-finite value or one deeper than
  64 levels. A report nests at most 6 levels, plus the `engine` object one level down.
  `MGSolidRenderPlan.manifest` throws the same two reasons. Tests run every entry point
  on a 512 KiB thread with values 100,000 levels deep.
* The result has `ok`, `reason`, `part`, `exitCode`, the report as `json` (`MGJSON`) and
  `text`: pretty-printed JSON with sorted keys, byte for byte what the tool prints.
  `MGSolidReport.Checks(doc)` gives the mesh and gear checks alone; `MGSolidSource(data:)`
  gives the `file` facts (lines, bytes, SHA-256, computed in Foundation).
* Refusal order after the document compiles: `check.meshOpen`, then
  `check.gearsInterpenetrate`, then the profile's refusal. A refused report still holds
  every field.

The report is built from sections (`MGSolidReport.sections`); a test keeps their keys
disjoint, so a later feature adds a section and its docs without changing the others.
The `annotations` section adds `annotations` and `placements` (see
[Annotations](#annotations-v2)) only for a document with annotations; such a document also
gets `legend.notes`.
For every shipped example and every JSON file under `docs/assets`, with and without
`--strict`, the tool's output without the fields added in this release is byte-identical to
the output of the release before (golden files in
`Examples/Solid3D/Tests/MartySolidCLITests/Golden`). `annotated-winch.json` is new: the
release before refuses it (`assembly.unknown.annotations`), so its golden pair holds this
release's output.

### Tiers per part and per motion

`partTiers` lists every part in part order: `{"part", "base", "motion", "tier", "source",
"ridesOn"}`. `motion` is `own` (the part's own joint moves; `tier` is that motion's
engine tier, `source` what moves it), `idle` (a joint that nothing moves), `rides`
(static on a moving ancestor, named by `ridesOn`) or `static`. Only `own` has a tier, as in
the claims: a part that only rides on a moving parent makes no motion claim. `base` is the
`repeat` base id. `motionTiers` has one entry per motion claim (once per authored part):
`{"id", "tier", "badge", "source"}`.

### Engine identity

Every `check`, `render` and `component check` output, the render `manifest.json` and
`marty-solid version` carry `engine`: `{"name": "MartyGraphics", "version",
"reportFormat", "assemblyVersions", "snapshotFormats", "executableSHA256"}`.
`version` is a constant in source (`MGEngine.version`): `"unreleased"` until a release
coordinator assigns a version (a test keeps it equal to the top `CHANGELOG.md` heading).
`reportFormat` (1) increments when a report field is renamed, removed or retyped, not when
one is added. `executableSHA256` is the SHA-256 of the running `marty-solid` binary,
computed at run time without git; it names the exact build. The engine does not know its
git commit: SwiftPM cannot pass a string into a build. Built from a source tarball, the
tool reports the version of that source and the hash of the binary you built; record the
commit next to the hash. A library host gets `MGEngine.identity` (no executable hash) and
can add its own.

### Checking a patch

`marty-solid check BASE.json --patch PATCH.json [--strict]` applies the patch with
`MGSolidParser.applying(data:to:)` and prints the report of the result, with `file` naming
the base, plus `patch`: `{"file", "applied", "fields", "changed", "refusedAt"}`. `fields`
lists what the patch sets (`title`, `params`, `constraints`, `steps`,
`parts.<id>.<key>`), sorted; `changed` lists the fields whose value in the document
source differs after the patch; `refusedAt` is `base` or `patch` when that document was
refused (then `changed` is absent). A patched document that compiles but fails a report
check or the strict profile has `applied: true`. The library call is
`MGSolidReport.check(data:patch:library:profile:engine:)`. Patch text is guarded before the
system parser runs: over 64 KiB `patch.bytes`, not UTF-8 JSON text or not parsed
`patch.json`, deeper than 64 levels `patch.depth`.

### Explainers

`marty-solid check` and `render` also take explainer documents (`"kind": "explainer"`): a 2D board, an assembly v2
as `solid`, or both, with one beat timeline and one report. See [EXPLAINER.md](EXPLAINER.md).

### Reasons and version

`marty-solid reasons` prints the catalog of every stable reason (pattern, meaning,
formats, warning or refusal) as JSON; see [REASONS.md](REASONS.md). Slots are typed
(`<shape>`, `<ident>`, `<id>`, …), so `MGSolidReasons.lookup` resolves an emitted reason
to its own entry, also when an author name holds `.missing.` or `.unknown.`.
`marty-solid version` prints the `engine` object.

## Worked examples

Small, complete models that `marty-solid check` accepts; a test keeps them valid. All of
them also pass `check --strict` with no warnings.

* [`idler-gearbox.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/idler-gearbox.json)
  (v2, 33 lines): a 16-tooth input, a 23-tooth idler and a 28-tooth output on shafts
  along Y (`rot` `[1, 0, 0, -90]`, confirmed by `expect.axisWorld`) inside a closed
  casing (a frame, two covers and a foot in one part). Four steps cut the front half of
  the casing away with one `section` (normal `[0, -1, 0]`), so the gears show behind solid
  cut walls; the last step shows the casing as a `ghost`. Captions come from facts: the
  idler turns at `{idler.speed|abs|frac}` ("16/23") the other way, and the output
  `{output.speed|frac}` ("4/7") the same way as the input, so the idler's size cancels
  out. Legend: "Solved 9" (three motions, four captions, two checks).

* [`annotated-winch.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/annotated-winch.json)
  (v2, 40 lines): a hand winch. A 14-tooth pinion with a crank drives a 42-tooth drum gear on
  shafts along Y; a rope and a weight hang from the drum. It uses all three
  [annotations](#annotations-v2): labels that show the tooth counts, two turn arrows whose senses
  the engine checks (`"sense": "ccw"` on the pinion, `"cw"` on the drum), a gravity force arrow
  under the weight, a motion arrow on the drum's rope side whose stated direction (`"expect": [0, 0, 1]`)
  the engine checks, and a measured centre distance (`{dim.centres}`, "56 mm"). Each step lists its
  annotations with `annotate`. The rope-side arrow shows in a step without `spin`: its anchor rides the
  drum, so while the drum turns it would leave the rope side (`annotation.pose.<id>`). Legend: "Solved 12" (two motions, seven annotations, two
  captions, one check) with the note "Arrow lengths are not to scale".

* [`horizontal-reduction.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/horizontal-reduction.json)
  (v2, 24 lines): a 15-tooth pinion driving a 40-tooth wheel on shafts laid along X
  (`rot` `[0, 1, 0, 90]` with joint `[0, 0, 1]`, both confirmed by `expect.axisWorld`), a
  support placed relative to its base and a collar relative to the wheel, captions filled
  from facts (`{wheel.speed|abs|frac}` gives "3/8", with a check that proves the sign),
  three claim checks and one `unchecked` caption. Legend: "Solved 8 · Not checked 1".

* [`slider-crank.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/slider-crank.json)
  (21 lines): a crank on a `revolute` joint with an `input` drive, a piston on a
  `prismatic` joint driven by `crankSlider` (crank radius 18 mm, rod 62 mm, so a
  36 mm stroke), and a connecting rod parented to the piston and driven by
  `crankRod`, so it stays between the wrist pin and the crank pin.
* [`propeller.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/propeller.json)
  (14 lines): a driven hub turning about −Z and one `blade` (span, chord, taper,
  pitch −40°, twist +28°, camber) copied three times with `repeat`, so the copies turn
  with the hub, leading edge first, steep at the hub and flatter at the tip.
* [`planetary.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/planetary.json)
  (53 lines): gear meshes, a fixed ring, a named carrier, explode windows and steps.
* [`planetary-components.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/planetary-components.json)
  (12 lines) and
  [`slider-crank-component.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/slider-crank-component.json)
  (8 lines): the same two teaching models built from [components](#components).

## Components

A component is a reusable, parameterised group of parts. An assembly uses it with
one short entry instead of describing its geometry again, so a model that explains a
new question pays only for what is new. Expansion happens before compiling: the
expanded parts get every check above (closed keys, limits, gear checks, the mesh
budget), and a refusal names the expanded part (`stage.planet2`).

### Use in an assembly

```json
{"v": 1, "kind": "assembly", "title": "Planetary gear set (from components)", "units": "mm",
 "parts": [
  {"id": "base", "use": "housingBase", "at": [0, 0, -1]},
  {"id": "stage", "use": "planetaryStage", "with": {"sunTeeth": 24, "planetTeeth": 18, "planets": 3}}
 ],
 "steps": [
  {"say": "Input: the brass sun gear (24 teeth) turns.", "highlight": ["stage.input"], "spin": 1},
  {"say": "Output: the carrier turns 24 / 84 of a turn per sun turn.", "highlight": ["stage.output"], "spin": 1},
  {"say": "Exploded along the shaft axis.", "explode": 1, "highlight": ["stage"], "camera": "iso"}
 ]}
```

A `use` entry has the keys `id`, `use` (the component id), and optional `with`
(parameter values, numbers only), `at` and `rot` (placement of the component's root
parts, the parts without a `parent`, in the frame of their parent), `parent` (an outer
part that the root parts are attached to) and `set`.

* **Ids.** Inner parts get the id `<instance>.<inner id>`, for example `stage.sun`,
  and `repeat` copies `stage.planet1…3`. Constraints, drives, parents, anchors and
  steps refer to them by these ids: the base id (`stage.planet`) means every copy, a
  copy id (`stage.planet2`) one copy. An anchor (`stage.input`, `stage.output`) names an
  inner part. The instance id alone (`stage`) means all its parts in a step `focus` or
  `highlight`; anywhere else it is refused (`ref.component.stage`). Authored ids are
  plain identifiers (no dot, at most 24 characters, `part.id`).
* **One namespace.** Part ids, `repeat` copy ids, instance ids and anchor names share
  one namespace, inside each component and over the whole document, checked again for
  the actual parameter values. A name used twice is refused: `id.duplicate.<id>` (for
  example a part `p` repeated twice beside an instance `p1`) or
  `component.anchor.<name>` (an anchor `pin1` beside the copy `pin1`).
* **`set`** changes fields of inner parts as if the component had written them, for
  example `{"set": {"pinion": {"drive": null, "material": "bronze"}}}` (`null`
  removes a field). Ids inside `set` are the outer document's ids. A compound train
  keys the second pinion to the first wheel this way:
  `{"id": "s2", "use": "spurPair", "at": [48, 0, 14], "set": {"pinion": {"parent": "s1.output", "at": [0, 0, 14], "joint": null, "drive": null}}}`.
  `at` / `rot` apply to the parts that are roots after `set`. `set` edits a repeated
  part through its base id, which changes every copy; one copy cannot be edited
  (`component.set.repeat.<id>`).
* **Patches.** `{"parts": {"stage": {"with": {"planets": 4}}}}` edits the `use` entry;
  `{"parts": {"stage.ring": {"material": "bronze"}}}` merges into its `set` (so a
  repeated part is patched through its base id, `stage.planet`).
* **Limits.** Nesting at most 3 levels (`component.depth`), cycles refused
  (`component.cycle.<id>`), resolved ids at most 64 characters including the `repeat`
  suffix (`component.id.length`). The part, constraint and step limits and the mesh
  budget count the expanded assembly (`parts.count`, `assembly.budget`).
* **Step lists.** A step's `focus` and `highlight` hold at most 16 entries as authored
  (`step.focus`, `step.highlight`). Then anchors resolve, instance ids expand to their
  wire part ids and duplicates merge; that list of wire names must also hold at most
  16 entries. A repeated part's base id then expands to all its copies, as in any
  document, and the copies are not counted: two instances with repeats can give more
  than 16 resolved parts.

### Definitions

```json
{"v": 1, "kind": "component", "id": "spurPair", "title": "Spur gear pair",
 "about": "Pinion (input) driving a wheel at the standard centre distance.",
 "params": {"pinionTeeth": {"default": 12, "min": 12, "max": 100, "integer": true},
            "module": {"default": 2, "min": 0.5, "max": 10, "about": "tooth size in mm"}},
 "checks": {"small": {"lt": [{"param": "pinionTeeth"}, 60]}},
 "parts": [{"id": "pinion", "shape": {"gear": {"teeth": {"param": "pinionTeeth"}, "module": {"param": "module"}, "width": 10}}, …}],
 "constraints": [{"gearMesh": {"a": "pinion", "b": "wheel"}}],
 "anchors": {"input": "pinion", "output": "wheel"}}
```

Required keys: `v`, `kind`, `id`, `title` (80 characters), `about` (one line, 160)
and `parts` (1–24 entries: plain parts as in an assembly, or `use` entries of other
components). Optional: `params` (at most 16; each `default`, `min`, `max`, optional
`integer` and `about`), `constraints` (32), `anchors` (8; name → inner id) and
`checks` (8). References inside a component name its own parts only
(`component.ref.unknown.<id>`). Definitions are at most 16 KiB.

**Expressions.** Any number in `parts` and `constraints` may be an expression object
with exactly one operator key: `{"param": "name"}`, `{"add": [a, …]}`,
`{"mul": [a, …]}`, `{"min": [a, …]}`, `{"max": [a, …]}` (1–8 operands),
`{"sub": [a, b]}`, `{"div": [a, b]}`, `{"neg": a}`, `{"pi": a}` (π × a),
`{"sin": a}` and `{"cos": a}` (degrees). Operands are numbers or expressions. There
are no strings, variables, loops or calls: evaluation is deterministic, at most
8 levels deep (`component.expr.depth`) and 4096 nodes per instance
(`component.expr.size`). Every result must be finite with magnitude at most 10⁶
(`component.expr.range`). Other errors: `component.expr.param.<name>` (unknown
parameter), `component.expr.div` (division by zero), `component.expr.<op>` (wrong
operand count) and `component.expr` (not an expression). A **check** is
`{"lt": [a, b]}`, `{"le": [a, b]}` or `{"int": a}` (a whole number) and refuses an
instance by name, for example `component.check.spacing` when
(2 × sunTeeth + 2 × planetTeeth) / planets is not whole.

**Parameter values** in `with`: `component.param.unknown.<name>`,
`component.param.value.<name>` (not a finite number), `component.param.range.<name>`
and `component.param.integer.<name>`. Other reasons: `component.unknown.<id>`,
`component.use.unknown.<key>`, `component.set.unknown.<id>`, `component.set.id`,
`component.anchor.<name>`, `component.duplicate.<id>`, and the closed-key reasons
`component.missing.<keys>` and `component.unknown.<keys>`.

### Library and catalog

`MGSolidLibrary.builtIn` holds the shipped components (JSON text in
`MGSolidBuiltInComponents.swift`, no bundle resources). A host copies it and calls
`register(_:)` with more definitions at runtime: each is validated, expanded at its
defaults and compiled on its own as an assembly; duplicate ids are refused.
`MGSolidParser.document(data:library:)` resolves `use` entries against a library
(default `builtIn`), and patches reuse the document's library. `catalog()` returns a
compact JSON list (id, title, about, parameters with defaults and ranges, inner part
ids, anchors), about 3.8 KB for the built-ins, so a model can discover them cheaply.

| Component | Parts | Key parameters (defaults) | Anchors |
| --- | --- | --- | --- |
| `spurPair` | pinion, wheel | pinionTeeth 12, wheelTeeth 36, module 2, width 10 | input pinion, output wheel |
| `planetaryStage` | sun, ring, carrier, planet × N | sunTeeth 24, planetTeeth 18, planets 3, module 2, width 12 | input sun, output carrier |
| `sliderCrank` | frame, crank, piston, rod | radius 18, rod 62, piston 14 (stroke = 2 × radius) | input crank, output piston |
| `propeller` | hub, blade × N | blades 3, span 110, chord 34, pitch −40, twist 28, hub 12 | input hub |
| `housingBase` | base, bolt × N | radius 84, thickness 7.5, bore 8, bolts 6 (top face at z = 0) | frame base |
| `shaftWithBearing` | shaft, lowerBearing, upperBearing | radius 6, length 80, bearingWidth 12 | input shaft |
| `fanStage` | hub, rotor (blade row), casing | blades 18, root 60, span 90, chord 40, stagger 35, twist 15 | input hub |

**Adding a component.** Write the definition, run
`marty-solid component check FILE.json` (it validates, compiles the component alone,
runs the mesh and gear checks, and prints its catalog entry and a `use` line), use it
from an assembly with `marty-solid check MODEL.json --component FILE.json`, then add
the JSON to `MGSolidBuiltInComponents.sources` in a reviewed pull request; the tests
compile every built-in at its defaults. Expression operator names are reserved: no
shape, joint, drive or constraint key may use them.

**Size.** The component versions of the worked examples are 12 lines and 927 bytes
for the planetary set (53 lines and 3,721 bytes by hand) and 8 lines and 754 bytes
for the slider-crank (21 lines and 1,670 bytes). Without the teaching steps, the
compact JSON shrinks from 2,477 to 255 bytes and from 943 to 177 bytes. The models
are close but not identical (the component planetary has no separate output key).

## Checks

`MGSolidChecks.gearMeshes` sweeps every gear pair over input angles and measures
2D tooth overlap in the gears' plane (`maxPenetration`) and engagement
(`minClearance`). `MGSolidChecks.pairInterference` sweeps one pair over a tooth
pitch at its standard centre distance. `MGAssembly.gearResiduals` checks the
tooth-ratio equations; each gear's turn is composed from its own joint and its
revolute parents, signed by joint axis direction against the pair axis
(`MGGearPair.axis`), relative to the carrier.

## Snapshot for other renderers

`MGSolidSnapshot.make(_:params:camera:aspect:lighting:)` exports one posed frame of an
assembly (format v1); `MGSolidSnapshot.make(_:step:params:…)` exports one step of a
compiled document (format v2, below):

| Field | Meaning |
| --- | --- |
| `positions`, `normals` | `Float` x, y, z per vertex, world space, Y-up, mm |
| `indices` | three `UInt32` per triangle |
| `triangleMaterials` | `UInt16` index into `materials` per triangle |
| `materials` | `id` plus `MGMaterialParameters` (sRGB base colour, metallic, roughness, clearcoat, transmission, ior, opacity) |
| `parts` | id, name, first triangle, triangle count, material |
| `camera` | target, yaw, pitch, distance, vertical field of view (`position` is derived) |
| `lighting` | directional lights (direction toward the scene, colour, intensity, shadow softness) and the procedural studio environment (gradient plus soft boxes) |
| `groundY`, `boundsMin`, `boundsMax`, `aspect` | framing and contact ground |

**Format v2** (`martygraphics.solid.snapshot/2`) adds:

| Field | Meaning |
| --- | --- |
| `parts[].opacity` | coverage 0.1–1 (ghosts included), always present; multiply with the material's `opacity` |
| `parts[].capFirstTriangle`, `parts[].capTriangleCount` | the cap triangles of a cut part, inside the part's range (absent when the part is not cut) |
| `materials[].emission` | `{"color": sRGB, "intensity": 0–4}` for an emissive part; its material `id` gets a suffix such as `aluminum+emissive.orange.2` |
| `section` | the step's plane in the snapshot's world frame (Y up, mm): `normal` (unit), `offset` (points with `normal · p > offset` are cut away) and the cut `parts` |
| `annotations` | the step's [annotations](#annotations-v2) (absent when it shows none): `arrows[]` (`id`, `meaning`, `style`, world `from` and `to`, unit `direction`, `colorRole`, `tier`, `text`, `firstTriangle`, `triangleCount`), `dimensions[]` (`id`, `kind`, world `points`, `value`, `unit`, `text`, `tier`, triangle range), `labels[]` (`id`, world `anchor`, filled `text`, `tier`, `chip`) and `placement[]` (see Placement; a step snapshot assumes a caption band). Arrow and dimension triangles come after every part triangle, so part ranges never move; their materials are `annotation.<role>`. They do not change the bounds or the default framing. |
| `highlight` | highlighted part ids (`MGSolidSnapshot.make(_:step:params:highlight:…)`; absent when none) |

The decoder dispatches on `format`. A `/1` file keeps exactly its v1 meaning: its bytes
are unchanged for the same assembly, and a `/1` file with any v2 field fails to decode. A
`/2` file is checked too (an opacity on every part, cap ranges inside their part, a unit
section normal, known section parts, three-number emission colours, and for annotations: finite
points, unit arrow directions, known meanings, roles and tiers, unique ids, triangle ranges after the
parts, in order and inside the list, placements of known ids, known highlight parts). A `/2` export
of a document without annotations and without highlight has the same bytes as before annotations
existed.

`format` is `martygraphics.solid.snapshot/1`; encode with `jsonData()` (an empty
assembly exports zero bounds and a unit framing camera, so the JSON stays finite).
Decoding checks every fixed-size slot (three numbers for colours, directions,
targets and bounds, eight per soft box, three floats per vertex, one normal per
vertex, indices inside the vertex list, one material per triangle, part ranges
inside the triangles) and fails instead of trapping later.

Decode snapshot text with `MGSolidSnapshot.decode(data:)` (it throws `MGSolidIssue`). Its
guards run before the system decoder, so hostile text cannot exhaust a small thread stack:
`solidSnapshot.bytes` (over `MGSolidSnapshot.maxBytes`, 256 MiB), `solidSnapshot.json` (not
valid UTF-8, or a raw NUL byte), `solidSnapshot.depth` (nesting deeper than 64 levels),
`solidSnapshot.number` (a number literal longer than 64 characters, or one that does not
read as a finite number, such as `1e999`); then anything the decoder or the checks above
refuse is `solidSnapshot.invalid`. A host that calls `JSONDecoder` on `MGSolidSnapshot`
directly skips these guards.

`Examples/Turbofan/Sources/MartySolidRT` maps a snapshot to an `MGRTScene` for
`MartyGraphicsPathTracer`: one mesh and instance per part, sRGB colours to linear,
metallic presets to GGX metals (base colour as F0), the rest to plastic, transmissive
presets to glass, clear coat carried over, the studio environment and soft boxes to an
environment map, and directional lights to hidden area lights. It sits in the example
so the two libraries stay independent.

## Limits

* SceneKit rasterisation: soft shadow maps, screen-space ambient occlusion,
  image-based lighting from a generated environment; no ray-traced reflections.
* Step sections are capped core cuts, by one plane per step. The renderer option
  `MGStudioOptions.section` is still the older fragment discard with uncapped faces, kept
  for compatibility. A section plane is fixed in each cut part's frame at the default
  input, so a moving part carries its cut. There are no multi-plane or box cutaways yet.
* Ghosts and part opacity use alpha blending; overlapping see-through parts can sort
  imperfectly.
* Gear contact is checked in 2D at sampled angles, not as continuous 3D contact.
* Frame lints compare bounding boxes, not meshes; a child that the box test calls near
  can still float. Parts are not checked against each other for collisions.
* Placeholders fill the title, step text and annotation text only (not part names). `<part>.worldSpeed`
  exists only when every turning ancestor's axis is parallel to the part's own.
* `frame.axis.off` checks only that the axis line meets the part's bounds; it does not
  also compare the axis with the bounds centre.
* No helical or bevel gears, belts, cams or general constraint solving beyond
  linear gear ratios and the slider-crank closed form.
