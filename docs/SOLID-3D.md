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
| Check report, render plan, camera framing, reason catalog | `Solid/MGSolidReport.swift`, `MGSolidRenderPlan.swift`, `MGSolidFraming.swift`, `MGSolidReasons.swift`, `MGEngine.swift` | Foundation only |
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
* **Bounds** (`MGSolidLimits`): 64 KiB, 48 authored parts (at most 96 wire parts
  after component expansion, `expandedParts`), 96 resolved parts (after `repeat`),
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

## Step pose and step visibility (v2)

A v2 step (and an explainer beat `view`) can move parts for that step only, and can hide
parts or show a part only in some steps.

```json
{"say": "Moving the arms aims the thrust.", "pose": {"pilot": {"with": {"leftShoulder": 40}}, "pilot.lowerArmR": {"rot": [-1, 0, 0, 50]}}, "show": ["plumeL"]},
{"say": "Inside one engine.", "hide": ["pilot"], "highlight": ["back"]}
```

### Pose

`pose` is an object of 1–16 entries (`step.pose`). Each entry names what it moves:

* a **component instance** (a top-level `use` id) takes `with`: parameter values merged
  into the entry's own `with` (`{"pilot": {"with": {"leftShoulder": 40}}}`);
* an **authored part** takes `rot` ([axisX, axisY, axisZ, degrees]), which replaces the
  part's own `rot` and keeps its `at`;
* a **part inside an instance** (`pilot.upperArmL`, or an anchor that names it,
  `pilot.leftShoulder`) takes `rot` the same way, through the `use` entry's `set`.

A key the id does not take, or a bad `rot`, is `step.pose.key`; an id that names none of
these, a `repeat` copy, or one part named twice is `step.pose.ref` (the report's `part`
gives the id). The engine checks each posed step against a compile of the whole
document with that pose applied:

* **Only placements change.** The parts, their order, shapes, names, materials,
  parents, joints, explode vectors and windows, opacity and light must stay the same. A
  `with` value out of range, an unknown parameter, a failed component check, or a value
  that changes more than placements (a `microTurbojet` diameter) is `step.pose.with`.
* **No solved mechanism moves.** A moved part (its placement changed, or it hangs below
  one) may not be a gear pair member or carrier, the part or source of a gear-mesh or
  crank drive, or a part the solver holds (`fixed`, `gearMesh`). The compiled motion
  (drives, ratios, motion sources, gear pairs), every drive tier and every engine fact
  must be unchanged. Otherwise `step.pose.solved`. So a pose never changes a number the
  step can show: its caption, checks and annotations use facts that hold at the pose,
  because they are the same facts. A mannequin's arms carrying engines may be posed (the
  engines' shafts turn by `input` drives); a gear in a mesh may not.
* **Facts at the pose.** Every fact a posed step displays (its caption, its `check`
  claims, the title and the text of every annotation it shows) must hold over the step's
  whole motion domain at its pose: every input its `spin` plays, at its explode value and
  placements. Joint and shape facts are the same facts (the rule above). A `dim.<id>` fact
  follows the rule shown dimensions follow (`dimensionHolds`): with `spin`, its anchors
  must keep their relative place during the motion, and its value at the pose must equal
  the measured value within 1e-9 × max(1, |value|, model diagonal) (the exact range with
  `over`). Otherwise the step is refused (`step.pose.fact`, `part` names the fact), also
  when no annotation shows the dimension. The `check` claims of an unposed step follow
  the same rule. So a `check` on a dimension can never stay "Checked" at a pose, or
  during a spin, where it is false.
* **The step is re-checked at its pose.** Gravity arrows, motion arrow `expect`,
  dimensions and every `dim.<id>` fact that the step shows are checked at the posed
  placements (`annotation.pose.<id>`, `text.pose.step.<n>`), and the frame lints run at
  each pose too (a posed child far from its parent adds `frame.child.far.<id>`).

The pose applies to that step only: its still, its story hold, its snapshot
(`MGSolidSnapshot.make` with `MGSolidStep.poseParameters`), its framing and its
unblocked-focus test. The plain view, `hero.png`, `exploded.png`, the loop and other
steps keep the authored placements. In `story.mp4` the camera move into a step also
moves the parts from the previous step's pose to this one (`MGStoryPlan.placements`,
rotation by quaternion slerp, translation in a straight line, eased with the camera),
with a real render at every frame; a cut jumps. While the parts move between two
different poses, no annotation is drawn (no label, arrow or dimension): the one gate
(`checkedAnnotations`) accepts only a step's own pose. Each posed step costs one more
compile of the document without its steps, annotations and title, reusing every mesh (measured
on the test Mac: 16 posed steps of a 76-part figure add about 0.07 s to `check`, release
build).
`MGSolidStep.pose` gives the posed placements (part id → placement in the parent frame);
`MGPoseParameters.placements` carries them through every pose function.

Read-back: the check report's `stepViews` lists, per step, `posed` (the parts whose own
placement changed) and `poseReadBack` (one line per moved part: world centre, size and
local +Z at the pose, `MGSolidDocument.poseReadBack`). A snapshot of a posed step lists
the posed parts in `posed`.

Not checked: collisions between posed parts, joint limits of a figure beyond the
component's parameter ranges, and the poses in between two steps (the story blend) are
not checked against any rule. The story's move test (`MGStoryPlan.routes`) tests each part's
box swept over the move's frames (the poses in between two steps as the story plays them),
for the parts the move draws solid (see "Routed moves" under "Story video").

### Hide and show

`hide` and `show` are arrays of 1–16 part ids (`step.hide`, `step.show`; an instance id
is one entry and names all its parts; a `repeat` base names every copy). A part that any
step lists in `show` is **show-only** (`MGSolidDocument.showOnly`): it shows only in the
steps that list it, and the plain view, `hero.png`, `exploded.png`, the loop and the
other steps hide it. `hide` hides parts in its step only. Hiding a part does not hide
the parts attached to it.

A hidden part is not drawn (`MGSolidPartView.hidden`, `MGSolidDocument.hiddenParts`),
is left out of every framing rule (focus context, whole model, hero, loop), never hides
another part (unblocked focus, label occlusion) and makes no claim in that view:

* a step may not list a part in both `hide` and `show` (`step.hide.both`);
* a step may not focus, highlight, ghost or cut a part it hides (`step.hide.use`; a
  show-only part a step does not show counts as hidden there);
* no annotation the step shows may be anchored on a hidden part (`step.hide.claim`; in
  the plain view, an annotation on a show-only part: `step.show.claim`);
* no displayed fact may belong to a hidden part: the text of every annotation the view
  shows, and the step's caption and `check` (`step.hide.fact`, `part` names the fact).
  The title shows in every frame, so it may not show a fact of a part that any view
  hides, the plain view included. The facts of a part are `<part>.<name>`, a `repeat`
  base's shared facts and `count.<base>`, `<instance>.ratio` (its input and output
  anchors) and `dim.<id>` (the dimension's anchors);
* a part that every view hides (the plain view, so `hero.png`, and every step) is never
  seen: it makes no motion claim in the legend. In an explainer the legend counts the
  motion of a part only once a presented beat displayed it (docs/EXPLAINER.md).

`MGSolidRenderer.show(_:)` hides their nodes; `MGSolidRenderer.worldBounds(_:…hidden:)` and
`frame(_:…hidden:)` take the parts to leave out (the SwiftUI explainer view passes the beat
view's `hiddenParts`). The snapshot of a view keeps every part range in part order and gives hidden parts no
triangles; it lists them in `hidden` (v2). The check report's `stepViews` gives each
step's `hidden` parts and `showOnly`. In `story.mp4` a beat shows its own visibility for
the whole beat (move and hold), like its cuts and ghosts.

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

A label's anchor and a pointer's tip must lie on the part they name, and every step or beat that shows them must
show the point: see [Anchor checks](#anchor-checks). A component anchor name gives its part's frame, not a point of
its own: `microTurbojet`'s `turbine` is `turbineWheel`, whose frame is at the intake plane (z = 0), so
`{"part": "e.turbine", "offset": [130, 0, 0]}` lies far from the wheel (`annotation.anchor.off.<id>`). Use
`{"part": "e.turbine", "point": "centre"}` for the middle of a part's mesh. Free text that names no part takes a
`{"world": [x, y, z]}` anchor.

### Text and tiers

Label, arrow and dimension text follows the v2 caption rules: placeholders with the modifiers
`inv`, `frac`, `pct` and `deg`, and rule N1 (`text.number.label.<id>`, `text.number.arrow.<id>`,
`text.number.dimension.<id>`). `abs` is refused (`text.sign.<name>`): no step proves a sign for an
annotation. Filled text is 1–60 Unicode scalars, authored text at most 240, and no character (grapheme cluster) of
the authored text may hold more than 8 scalars (`text.grapheme`, `part` names the annotation) (`label.text.<id>`,
`arrow.text.<id>`, `dimension.text.form.<id>`). A label or arrow may carry `"unchecked": "<why>"`
(1–60, `label.unchecked.<id>`, `arrow.unchecked.<id>`; an arrow needs `text` for it,
`arrow.unchecked.text.<id>`): its text may
then type numbers and its claim is Described. A filled text over 40 scalars draws on two lines
(`MGAnnotationLayout.lines`, see Placement).

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
is 15 % of the model's bounding diagonal at the default input (in a step, of its motion arrow size; see below).

While a view plays, a motion line arrow follows the exact velocity at each pose; it hides while its anchor has no
velocity. A turn arrow rides
the frame its part turns in (the parent frame), so it does not spin with the part.

Appearance (the same in every renderer): shaft radius 0.6 % of the bounding diagonal, head 4 shaft
radii long and 2.5 wide. **Motion arrows** (turn and line) take the step's focus size instead
(`MGSolidDocument.motionArrowDiagonal(step:)`): in a step with a `focus`, or else a `highlight` or
`section`, the diagonal of those parts' posed box, when it is at most 75 % of the model's diagonal; the
plain view and other steps keep the model's diagonal. Their shaft, head and automatic line length scale
with it, and a turn arc's radius is the larger of 8 shaft radii and 1.15 × the part's widest radius
about its axis. So the turn arrow of a small shaft seen close up stays near the shaft instead of
covering the cutaway. Force, flow and pointer arrows and dimension lines keep the model's size. Colour roles: force `warn`, flow `accent`, motion `good`, pointer `ink` (the
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
  may be at most 12 (`annotations.visible`). The refused report adds `visibility`:
  `{"annotation", "cause", "count", "limit"}`. `annotation` is the first annotation over the limit in
  authored order (labels, then arrows, then dimensions; the 13th id), also given as `part`. `count` is the
  number that would show at once and `limit` is 12. `cause` is `nosteps` (the document has no step, so the
  plain view shows all of them) or `unannotated` (it has steps, but none has `annotate`). No step is at
  fault, so the report names none. The repair is to remove annotations down to 12, or to add `annotate`
  to the steps.
* When any step has `annotate`, each step shows exactly its list (0–12 ids: `step.annotate`,
  `step.annotate.count`, `step.annotate.ref.<id>`). A step without the key shows none, and the plain view
  shows none. A list over 12 (`step.annotate.count`) adds `visibility` with cause `step` and `"step"`
  (1-based).
* An explainer's solid applies the limit per beat: with more than 12 annotations it is stepped even before
  any beat has `annotate`, so each beat shows only its own list (at most 12, `view.annotate.count`, cause
  `beat`). With 12 or fewer it follows the rules above unchanged ([EXPLAINER.md](EXPLAINER.md)). An annotation that no step shows is the warning `annotation.unused.<id>` (strict refuses).
* `MGSolidDocument.visibleAnnotations(step:)` and `view(step:).annotations` give the ids.

### Limits

| Limit | Value | Reason |
| --- | --- | --- |
| Labels, arrows, dimensions per document | 32, 32, 16 (`MGSolidAnnotationLimits`) | `labels.count`, `arrows.count`, `dimensions.count` |
| Visible at once | 12 | `annotations.visible`, `step.annotate.count` |
| Text | 1–60 scalars filled (two lines over 40), 240 authored; `unchecked` 1–60 | as above |
| Occlusion ray tests | 2,000,000 triangle tests per frame | over it, `occluded` is null and the anchor is drawn as visible |

Arrow and dimension pieces join the mesh budget with exact counts before any mesh is built: a line
arrow is 48 triangles, a turn arrow 784, a distance 96 (160 with `along`), an angle 832
(`assembly.budget`).

### Placement

`MGAnnotationLayout.place(_:)` is one pure function. The SwiftUI overlay, `marty-solid render` and the
snapshot call it through `MGSolidAnnotations.frame(document:view:params:camera:…)`.

1. A core perspective projection of `MGSolidCamera` (`MGAnnotationProjection`, the same as
   `MGSolidRenderer.project`).
2. Text box: font f = clamp(round(0.022 × view height), 11, 20) px; box width 0.58 × f × (scalars of the
   longest line) + 12 px, height 1.3 × f × lines + 8 px. A text up to 40 scalars is one line (its box is the
   same as in earlier releases); a longer one (at most 60) breaks into two at the space nearest its middle
   whose halves are at most 40 scalars each (else at the middle character boundary;
   `MGAnnotationLayout.lines`). A line still over 40 scalars (no legal break, for example a host's text over 80
   scalars) is cut at a character boundary and ends in "…". So a box is at most 0.58 × f × 40 + 12 px wide and
   2.6 × f + 8 px high, whatever the text. Tests cover CJK, emoji and combining-mark text.
   Renderers draw one row per line and shrink their font until every real line fits the box
   (`MGSolidOverlay.fit`). A test lays out five 60-scalar labels at 1280×720, 1280×800, 1440×720,
   1280×1280, 1280×2560, 1920×1080, 3840×2160 and 1600×3200: every box inside the view, none
   overlapping, every line fitted, the same layout twice.
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

### Anchor checks

Two rules check where the dot of a label and the tip of a pointer arrow land. The anchor of a label is its `at`; the
anchor of a pointer is its tip (`to`). Force, flow and motion arrows and dimensions are not tested by these two rules;
[Arrow visibility](#arrow-visibility) tests every arrow's shaft and head (pointers too).

**On its part** (`annotation.anchor.off.<id>`). Two tests:

1. The anchor lies in its part's oriented box (the box of the part's mesh, in the part's own frame), or at most
   `max(5 % of that box's diagonal, 0.5 % of the drawn model's diagonal)` mm outside it
   (`MGAnnotationAnchorRules.partShare`, `modelShare`). The drawn model is the parts that the views showing the
   annotation draw, at their poses; hidden parts are left out (all parts when no view shows it). This test is in the
   part's own frame, so it holds in every pose; its issue has no step.
2. No other part's solid comes nearer to the anchor than its own part's box, by more than the precision epsilon at the
   dot (below). Each view uses its own geometry: the anchor's distance to its own part's box and to every other part
   are measured at that view's pose, in anchor-relative coordinates. A view is skipped only when, in that view, the
   anchor is within the epsilon of its own part's box. This test runs at the pose of every view that shows the annotation: the plain view at the default pose
   when it shows it, and each step or beat at its still's pose (a beat's view is its solid step). The first view where
   a part is nearer is the issue's `step` (and `beat`), and that part is `closer`. A part's solid is its surface or its
   inside: the anchor is inside when a segment from it along +X crosses the part's surface an odd number of times
   (watertight crossings). So an L-shaped part whose box holds empty space does not claim an anchor in that space.

The nearer-part search is exact and stops early (`MGMeshChunks.nearer`): a part whose oriented box is not nearer costs
one box test; the part's triangles are read once into runs of 64 with their boxes; runs farther than the own part's
distance are skipped; the search stops at the first nearer triangle (in run order), and `closerDistance` is that
triangle's distance, which is 0 when the anchor lies on that triangle (a dot on the part's face). When no triangle is
nearer and the anchor lies inside the part (watertight parity), `closerDistance` is also 0; an anchor inside a part can
still report a positive distance to a face found first. So `closer` is the first part found (assembly order) and
`closerDistance` the first distance found, not necessarily the nearest.
Every triangle read, run-box test and triangle test of one document counts against 3,000,000
(`MGAnnotationAnchorRules.surfaceTests`). When the budget runs out the answer is unknown: the anchor is
`annotation.anchor.untested.<id>` with the view and `"budget": "nearerPart"`, never off. A world anchor names no part and is not tested. The first
test is a document warning (`MGSolidDocument.offPartAnchors`), so the compile's strict profile refuses it too; the
second test's `off` issues are document warnings as well, and its `untested` issues are refused by the strict check
report.

**Visible in each step or beat that shows it** (`annotation.anchor.hidden.<id>`). The check frames each step still as
`marty-solid render` does at 1280 × 800 (`MGSolidDocument.stepAnchorIssues`: the step's shot, its title and caption
bands, the unblocked-focus rule and its automatic ghosts) and each explainer beat as its still's solid pane
(`MGExplainerFrame.beatAnchorIssues`), at the still's pose. For each label and pointer the view shows, in view order,
the first cause found is the issue:

| Cause | When |
| --- | --- |
| `hidden` | the anchor's part is hidden in the view (a safety net: `step.hide.claim` already refuses a step that hides a part its annotations name) |
| `ghosted` | the view draws the anchor's part fainter than its own opacity: step `ghost`, or an automatic ghost of the unblocked-focus rule |
| `offscreen` | the anchor projects outside the view (the whole still or pane, bands included), or lies behind the camera |
| `occluded` | another part is the first surface on the segment from the camera to the anchor (`by` names it) |
| `untested` | the view's line-of-sight tests ran out of budget before this anchor (`annotation.anchor.untested.<id>`, `"budget": "lineOfSight"`) |

The segment test is the watertight ray test of the unblocked-focus rule against every part the view draws with a
coverage of 0.5 or more. Coverage is what the renderer draws: the view opacity (the part's `opacity` and any ghost)
times the material's own coverage (`MGMaterialPreset.coverage`: 0.22 for `glass`, 1 for every other preset), so glass
hides no anchor. A cut part tests its cut mesh. A part blocks when it crosses the segment before the anchor (less the
precision epsilon at the anchor) and before the first crossing of the anchor's own part. So an anchor at the centre of
its part, seen through its own surface, is visible, and an anchor in the air in front of a part is not hidden by it. A
blocker hit that lies on the anchor's own part (as the view draws it) within the precision epsilon at the hit point is
a coincident surface, a tie, not an occlusion: the own part is there too, so the anchor is visible. Two touching parts
therefore give the same result whichever of them the anchor names. A separate part in front of the anchor hides it
unless its hit lies within that epsilon of the own part (0.01 mm and more are caught in the tests, also with the model
driven to 10⁶ mm).

**Anchor-relative coordinates and the precision epsilon.** Every visibility, tie and nearer-part test runs in
anchor-relative coordinates (`mgAnchorRelative`): the anchor point is subtracted, in double precision, from the camera
and from each part's placement before any test, and hit points are kept relative to the dot. Each part's triangles are
tested in the part's own frame, reached from those relative coordinates. At a point `p` the epsilon is
`1e-6 × max(1, |p − anchor|) + 1e-4` mm (`mgPrecision`): 1.01e-4 mm at the dot, at most 2e-4 mm within 100 mm of it,
1.1e-3 mm 1 m from it. It depends only on the distance from the dot, so neither the size of the model, nor hidden or
distant parts, nor where drives or poses move the model (a model driven to 10⁶ mm) widens it. A world anchor has no
own part: any crossing before it hides it. **Cut parts:** when the view's section cuts the anchor's
own part and the anchor lies in that part's box on the kept side of the cut or on the cut face, the parts inside the
cut part do not hide it; parts outside it still do. Inside is tested in the cut part's own frame: every corner of the
other part's mesh box, posed and taken into that frame, lies in the cut part's mesh box grown by 0.5 % of the diagonal
of the parts the view draws. So a rotated cut part never exempts a part that only its world-axis box holds. The anchor
counts as on the cut face or in the box within the precision epsilon.

The tests of one view spend at most 3,000,000 triangle tests (`MGAnnotationAnchorRules.tests`), the tie tests
included. The anchor whose line-of-sight test would pass the budget, and every anchor of that view after it, is `untested`
(`annotation.anchor.untested.<id>`, also listed in `anchorUntested`); the other causes are still tested for it.
Strict does not pass what it did not check: the strict check report refuses an untested anchor. The standard profile
warns.

The standard profile only warns: the renderers keep drawing a blocked anchor with a hollow dot and a dashed leader.
The strict check report (`marty-solid check --strict`, `MGSolidReport`, `MGExplainerReport`) refuses the first view
issue, after every other refusal. The view rules need each still's camera, so a compile with
`MGSolidParser.document(profile: .strict)` does not give them. The report lists every issue in `anchorIssues`; this one
is the jet-suit example before its fix:

```json
{"id": "lComb", "kind": "label", "reason": "annotation.anchor.hidden.lComb", "cause": "occluded", "part": "back.combustor",
 "by": "back.casing", "closer": null, "closerDistance": null, "step": 6, "beat": null, "point": [30, 258, 1362],
 "distance": null, "tolerance": null,
 "fix": "`back.casing` hides the anchor: move the anchor (`at`) to a face of `back.combustor` that faces the camera, change the camera (camera, orbit), or ghost `back.casing` in this view."}
```

`step` and `beat` are 1-based; `point` is the anchor in the kernel world (Z up, mm) at the view's pose; `distance`,
`tolerance` and, when another part is nearer, `closer` and `closerDistance` (mm, the first nearer triangle found) are
set for `offpart`. A refusal for
an anchor reason also adds `anchor`: the issue it names. Each issue also has `suggest`, `noSuggest` and `repair`
([Anchor suggestions](#anchor-suggestions)).

### Anchor suggestions

For every off or hidden issue (`offpart`, `hidden`, `ghosted`, `offscreen`, `occluded`; not `untested`), the check
report gives `suggest`: an anchor that passes both rules above in every view that shows the label or pointer, in the
form a document writes it, `{"part": "<part>", "offset": [x, y, z]}` (the part's own frame, mm, rounded to 0.001 mm;
`"point"` takes only `"centre"`, so a suggestion is always an offset). `part` is the resolved part (a component anchor
name gives its part). For a pointer it is the tip (`to`). One suggestion serves all issues of the same annotation
(`MGSolidDocument.anchorSuggestions(for:views:)`).

The search, for each such annotation in issue order:

1. For each view that shows it (the framed step or beat stills above), sample points of the part as that view draws it
   (a cut part's cut mesh): the 24 triangles nearest to the authored dot (their nearest points), 24 triangle centroids
   spread over the mesh, 16 centroids of a cut's cap triangles, the box centre, and a 12 × 12 grid of rays across the
   part as the camera sees it (spanning its box diagonal in the plane through the box centre that faces the camera).
   A ray from the camera through each sample, to just past it, gives the first hit on the part; the candidate is that
   hit moved 0.05 mm further along the ray, into the part (`MGAnnotationAnchorRules.inset`). A cap sample is also a
   candidate itself, 0.05 mm to the kept side. An annotation that no view shows takes its part's points, 0.05 mm inward.
2. Candidates are rounded to 0.001 mm and sorted: on a cut face first when a view cuts the part, then by distance to
   the authored dot, then by generation order.
3. The first candidate that passes the view rule (`MGAnchorViewRule.test`, the code `anchorIssues` runs) in every view
   that shows the annotation, and then the off-part rule (`MGSolidDocument.offPartIssue`), is the suggestion. A
   cheaper screen runs first: the rule's own segment test through runs of 64 triangles; it can only drop a candidate
   (a coincident-surface tie counts as hidden there), never pass one.
4. When none passes, a second pass adds denser samples (48 nearest, up to 512 centroids, 32 cap centroids, a 24 × 24
   grid) and checks only the new candidates.
5. When still none passes, `suggest` is null and `noSuggest` says why: the first view where no candidate passes on its
   own names the cause, and when every view passes some candidate the cause is that none passes in all of them.

**Form.** A suggestion is always written in a form the parser accepts: `{"part", "offset": [x, y, z]}` with every
coordinate within ±4000 mm (`anchor.offset`), or `{"part", "point": "centre"}` (the part's mesh centre, which is
also a candidate and is checked like the others). A point whose offset would be out of range is never a candidate;
when only such points would pass, the cause is `form`.

**Re-check with the new framing.** The camera of a step or beat still fits the anchors it shows, so moving a dot can
change the framing: it can expose another part in front of that dot, or hide another annotation that had no issue.
Every suggestion is therefore checked again with the document it makes (`MGAnnotationAnchorReport.verify`): the
document with every suggestion applied is parsed, compiled, framed and checked again. The set is accepted only when
that check shows **no issue for any suggested annotation and no issue for any annotation that had none** in the report.
Otherwise:

* a suggestion whose annotation still has an issue is searched again in the copy's framing, at most twice
  (`MGAnnotationAnchorRules.retries`), then dropped (`framing`, or `conflict` when another suggestion caused the
  issue, see below);
* an annotation that had no issue and now has one blames the suggestions shown in the same view (every suggestion when
  none is); each is searched again, avoiding its last anchor and the points within max(1 mm, 10 % of its part's box
  diagonal) of it, at most twice, then dropped with cause `conflict` and `other` naming that annotation;
* a suggested annotation that passed an earlier re-check with the same anchor and fails now was broken by another
  suggestion (two or more suggestions that keep breaking each other): the first, in sorted id order, of those that
  changed since and are shown in the same view (of those shown with it when none changed). It is searched again like
  any failing suggestion; when it is dropped, the cause is `conflict` with `other` naming that suggestion. `framing`
  remains only when no other suggestion caused the issue;
* a copy that does not compile drops every suggestion of that set (`form`).

The set is checked again after each change, at most 6 full re-checks in all (`MGAnnotationAnchorRules.recheckRounds`);
when they run out first, every remaining suggestion is dropped: with cause `conflict` and `other` when its issue was
attributed to another suggestion or it was blamed for another annotation's new issue (so all three suggestions of a
three-way cycle are conflicts), else with cause `framing`. So the printed suggestions, all applied together, parse,
clear every suggested annotation and give no other annotation an issue. Known limit (a follow-up): when two
suggestions each pass on their own but fail together already in the first re-check, no earlier pass exists to
attribute the issue, so the cause is `framing` without `other`; those suggestions are not printed, so no unsafe
suggestion results.

`noSuggest` is `{"cause", "code", "step", "beat", "by", "other", "samples", "alternatives"}` (`step` and `beat`
1-based):

| `code` | `cause` | `alternatives` |
| --- | --- | --- |
| `occluded` | `part fully hidden in step N` (or `beat N`); `by` is the part in the way of the nearest sample | leave the annotation out of that view's `annotate` (`view.annotate`) list, ghost `by` in that view, or change that view's camera |
| `hidden` | `part hidden in step N` | leave it out of the list, show the part, or anchor it on a part the view shows |
| `ghosted` | `part ghosted in step N` | leave it out of the list, do not ghost the part, or change the camera |
| `offscreen` | `part off screen in step N` | leave it out of the list, or change the camera |
| `nocommonpoint` | no point of the part is visible in every view that shows it | show it in fewer views, or use one label per view |
| `budget` | suggestion budget ran out | simpler parts near the anchor, or fewer labels |
| `form` | no visible point of the part can be written as an anchor | anchor it on a part whose frame is near its mesh, or use a world anchor for free text |
| `framing` | no anchor stays visible once the framing changes | leave it out of the views that hide it, set those cameras, or ghost the part in the way |
| `conflict` | every anchor tried conflicts with `other` once applied: it hides `other` (`other` had no issue before), or `other`'s suggestion keeps hiding this one | show the two in different views, move `other` as well, or set the camera of the view that shows both |

"Fully hidden" means that none of the `samples` candidates passed: the search is sampled, not exhaustive. Budgets of one
report: one search for one annotation spends at most 8,000,000 tests (`MGAnnotationAnchorRules.suggestTests`), and an
annotation is searched at most 3 times (the first search and 2 retries), so at most 24,000,000; all searches of the
report together, retries included, spend at most 64,000,000 (`suggestDocumentTests`, one shared budget,
`MGSuggestionBudget`). A test is every triangle read for the samples and runs, every run-box and ray–triangle test,
and the view rule's own count. On top of the searches come at most 6 full re-checks (`recheckRounds`), each a parse,
compile, framing and anchor check of the document with the suggestions applied, with the check's own budgets
(3,000,000 triangle tests per view, 3,000,000 nearer-part tests). The search is deterministic (views in order, samples in a
fixed order, no dictionary order). A suggestion is checked with a fresh view budget; in the full check the anchors
before it in the same view share that view's 3,000,000 tests.

`fix` says in one sentence what is wrong, then names the suggestion (`Use {"part": …, "offset": […]} for the anchor
(`at`): it lies on … and passes the anchor rules in every view that shows …`), or the cause and the alternatives; an
off-part fix also names the world anchor for free text. It proposes the part's centre (`{"point": "centre"}`) only when
the rules were checked to pass it. `repair` is one line built from these fields, at most 400 Unicode scalars
(`MGAnnotationAnchorIssue.repair`): what is wrong, where, and the anchor to use. For example, a 40 mm core box inside
a closed 200 mm shell box:

```text
Label l1 (step 1) is hidden behind shell. No visible point: part fully hidden in step 1. Leave l1 out of step 1's annotate list, ghost `shell` in step 1, or change step 1's camera.
```

and a label 200 mm above the centre of a 40 mm box beside them: `Label l1 is 180.0 mm off side (at most 3.5 mm). Use
anchor {"part": "side", "offset": [-0.011, 0.042, 19.975]}.` (a point on the top face, 0.05 mm inside along the
camera ray; the offset depends on the camera). A tool can pass `repair` straight to a model. The synthetic explainers in
`docs/fixtures/anchor-suggest` reproduce the round-2f geometry (inner parts behind a casing, off-part dots, a cut
casing, a posed beat, component instance parts, a pointer) with neutral names: applying every `suggest` to a copy
clears that annotation's anchor issues.

Not tested: the visibility of anchors in the plain view (`hero.png`, `solid-0.png`; the nearer-part test does test the
plain view when it shows the annotation), the poses during a step's or beat's spin and camera moves,
other sizes than 1280 × 800, and whether the dot is covered by another text, a band or the legend. A part made of
overlapping closed shapes can count a point inside two of them as outside; its nearest-triangle distance is used then.

### Arrow visibility

An arrow drawn inside a casing, or behind a part, says nothing. In every step or beat still that shows an arrow (force,
flow, motion or pointer; `MGSolidDocument.arrowIssues`), the check samples the arrow as the renderer draws it at the
still's pose, motion sense and step (`MGSolidAnnotations.primitives`): 16 points along the drawn shaft, evenly by
length (a turn arrow's arc counts its chords; the shaft ends at the head's base), and 3 points along the head's axis,
at 1/6, 1/2 and 5/6 of its length from its base (`MGAnnotationArrowRules`). An arrow shorter than its head has head
samples only; an arrow the view does not draw (a motion arrow on a still anchor) is not tested.

Each sample is tested from the still's camera with the line-of-sight rule of the anchor checks (`MGAnchorViewRule`):

* off screen (outside the still's 1280 × 800 view, or behind the camera): not visible;
* else hidden when a blocking part (one the view does not hide, with a coverage of 0.5 or more: view opacity times
  `MGMaterialPreset.coverage`, so a ghost or glass does not block; a cut part tests its cut mesh) crosses the segment
  from the camera to the sample before the sample less the precision epsilon there, with the watertight ray test, in
  sample-relative coordinates (`mgAnchorRelative`, the epsilon `mgPrecision`); the nearest such part hides it;
* the cut exception: when the view cuts a part the arrow is anchored on (`from`, `to` or `on`) and the sample lies in
  that part's box on the kept side (or on the cut face), the parts whose box lies inside that part's box (in its own
  frame, grown by 0.5 % of the drawn model's diagonal) do not hide it;
* unlike an anchor, an arrow has no own-part exception: the parts it is anchored on hide it too, so an arrow from a
  nozzle to its intake lip inside a closed casing is hidden.

The arrow is **hidden** (`annotation.arrow.hidden.<id>`) in a view when less than half of all its samples are visible
(`minVisibleShare` 0.5), or fewer than 2 of its 3 head samples are (`minHeadSamples`). So a weight arrow that starts at
a body's centre passes while most of it and its head show; an arrow whose head ends inside a part is hidden. One view
may spend 3,000,000 tests (`MGAnnotationArrowRules.tests`: every run-box and triangle test through runs of 64
triangles, and building a part's runs costs its triangle count, once per view); the arrow whose test would pass it,
and every later arrow of that view, is **untested** (`annotation.arrow.untested.<id>`). A sample whose line of sight
meets no part box needs no test. The standard profile warns; the strict check report refuses the first arrow issue in
step or beat order, after the anchor refusals (`MGSolidReasons.reportStrictPrefixes`; the compile does not refuse it,
because it needs each still's camera).

The report lists every arrow issue in `arrowIssues` (documents with annotations), and a refusal for an arrow reason adds
`arrow`, the issue it names: `{"id", "meaning", "reason", "cause", "step", "beat", "by", "samples", "visible", "share",
"head", "headVisible", "offScreen", "fix", "suggest", "noSuggest", "repair"}` (`step` and `beat` 1-based; `by` the part
that hides the most samples, ties in assembly order, null when none does; `share` the visible share, rounded down to
0.001). `repair` is one line of at most 400 Unicode scalars, for example:

```text
Arrow push (beat 2) is 5 % visible, hidden behind engine.casing; its head is hidden. Use {"from": {"part": "engine.nozzle", "offset": [-18.047, -46.987, 0]}, "to": {"part": "engine.intakeLip", "offset": [-18.047, -46.987, 0]}}.
```

**Suggested move** (`MGSolidDocument.arrowSuggestions`). For a hidden force, flow or pointer arrow, `suggest` is a move
that passes the rule in every view that shows the arrow: `{"from": anchor, "to": anchor}` for a force or flow arrow
(both ends move by the same offset, so the arrow keeps its direction and length), `{"from": anchor}` for a pointer (its
tip stays; only its start moves). At the pose of the first view that shows the arrow, with `u` the arrow's direction,
`c` the direction toward that view's camera without its `u` part and `e1`, `e2` a basis perpendicular to `u`, the
offsets tried are the directions `u, −u, c, −c, e1, −e1, e2, −e2` (a pointer: `c, −c, e1, −e1, e2, −e2, −u`) times
`k × S`, `k = 1 … 8`, where `S = max(the blocking part's box diagonal, the arrow's length) / 4` (at least 0.5 mm),
smallest offset first, then in direction order. An end on a part moves in that part's frame (the offset taken into
the frame at that pose; the resolved part id), rounded to 0.001 mm; a world end moves in the world. A candidate outside
±4000 mm, or a pointer start within 4 shaft radii of its tip, is skipped. A force or flow arrow says something with its
vector, so a candidate is kept only when the moved arrow's vector (end minus start) equals the authored one in **every**
view that shows it, within the precision epsilon at that vector plus 0.002 mm for rounding both ends
(`MGAnnotationArrowRules.keepsVector`): when the ends ride on parts that turn differently between views, an offset
taken into their frames at one pose moves them apart at another. The first candidate whose samples are all visible in
every view is the suggestion, else the first that passes the rule in every view. After the re-check, every move is
checked once more against the authored arrow in every view (`measure`). A pointer keeps its tip; only its start moves,
so its vector is not kept. A motion arrow shows its anchor's motion and gets none (`code` `motion`). With none,
`suggest` is null and `noSuggest` is `{"cause", "code", "step", "beat", "by", "other", "samples", "alternatives"}`
(`code`: `motion`, `pose` (no candidate keeps the vector in every view), `noclearoffset`, `budget`, `form`, `framing`
or `conflict`; alternatives: leave the arrow out of that view's `annotate` list, ghost the part in the way, or change
that view's camera).

**Re-check.** A move changes the framing too (a still's camera fits the arrow ends it shows), so the moves are checked
again once applied, as anchor suggestions are (`MGAnnotationArrowReport.verify`): the document with every move applied
is compiled, framed and checked again. The set is accepted only when no moved arrow has an arrow issue and no
annotation (arrow, label or pointer) that had no issue now has one. Otherwise a moved arrow that still fails is
searched again in the copy's framing (at most twice) and then dropped (`framing`); the moves shown in the same view as
a newly failing annotation are searched again away from their last start (at most twice) and then dropped
(`conflict`, `other` naming it); a copy that does not compile drops the set (`form`). At most 6 re-checks; when they
run out, the remaining moves are dropped (`framing`). `suggest` gives the anchors exactly as a document writes them.
Budgets: one search for one arrow spends at most 8,000,000 tests, and all searches of one report together, the
re-check's searches included, at most 64,000,000 (`suggestTests`, `suggestDocumentTests`; one shared budget object,
`MGAnnotationArrowReport.repair`); each re-check runs the check's own budgets.

**All suggestions together** (`MGSuggestionUnion.verifyTogether`). After each family's own re-check, a report
applies every suggestion it would print, anchor suggestions and arrow moves, to one copy and checks it again with
every anchor and arrow rule on every annotation. This runs for every non-empty union, also one that holds only anchor
suggestions (the anchor family's own re-check does not test arrow visibility) or only arrow moves. The accept rule is
the one above: no suggested annotation (label, pointer or arrow) has an issue and no annotation that had none has one.
No new search runs in this check. A suggestion whose annotation still has an issue is dropped with cause `conflict`
and `other` naming the first suggestion of the other family (sorted ids) shown in the same view (of all of them when
none is), or with cause `framing` when the union holds none of the other family. An annotation that had no issue and
now has one drops the suggestions shown in the same view (all when none is), each with `conflict` and `other` naming
it. A refused copy drops every suggestion (`form`). The remaining set is checked again until it is accepted or empty,
at most 12 checks (`MGSuggestionUnion.unionRounds`); when they run out, every remaining suggestion is dropped. So every
printed suggestion, anchors and arrows, can be applied at once.

The synthetic explainer `docs/fixtures/arrow-visibility/arrow-in-casing.explainer.json` (a figure with one engine on
its back, neutral names) holds a thrust arrow from the nozzle to the intake lip, inside the casing: strict refuses it
(5 % visible, `engine.casing` in the way), and its `suggest`, applied, passes strict.

Not tested: arrows in the plain view (`hero.png`, `solid-0.png`), the poses during a spin and camera moves, other sizes
than 1280 × 800, whether a sample is covered by text, a band or the legend, and how thick the drawn shaft is (the
samples lie on its axis). Dimensions are not tested.

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
nothing moves, a turn axis that misses its own jointed part, an annotation that no step shows, and a label or pointer
anchor off its part. The strict check report also refuses a label or pointer anchor that a step still does not show,
or that its budget left untested ([Anchor checks](#anchor-checks)). The child-frame warnings
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
| `annotation.anchor.off.<id>` | A label's anchor or a pointer's tip lies off the part it names, or another part is nearer to it ([Anchor checks](#anchor-checks)). | refused |
| `annotation.anchor.hidden.<id>` | The check report only: a step still shows a label or pointer whose anchor it does not show (occluded, hidden, ghosted, off screen). | refused by the check report |
| `annotation.anchor.untested.<id>` | The check report only: the view's line-of-sight budget, or the document's nearer-part budget, ran out before this anchor. | refused by the check report |

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
* `MGSolidReport.make(_:profile:source:engine:anchorViews:)` reports on a compiled document (compile it
  with the standard profile, so the report can show what `.strict` refuses). `anchorViews` (default true) runs the
  anchor view rule on every step still; an explainer passes false and tests its beats.
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
  `check.gearsInterpenetrate`, then the profile's refusal, then (strict) the first
  `annotation.anchor.hidden.<id>` or `annotation.anchor.untested.<id>` (the nearer-part test's untested anchors in
  authored order, then the view issues in step order). A refused report still holds
  every field.

The report is built from sections (`MGSolidReport.sections`); a test keeps their keys
disjoint, so a later feature adds a section and its docs without changing the others.
The `annotations` section adds `annotations` and `placements` (see
[Annotations](#annotations-v2)) only for a document with annotations; such a document also
gets `legend.notes`, `anchorIssues`, `anchorUntested` and `arrowIssues`, and `warnings` ends with one
`annotation.anchor.hidden.<id>` or `annotation.anchor.untested.<id>` per step issue ([Anchor checks](#anchor-checks)),
then one `annotation.arrow.hidden.<id>` or `annotation.arrow.untested.<id>` per step arrow issue
([Arrow visibility](#arrow-visibility)).
For every shipped example and every JSON file under `docs/assets`, with and without
`--strict`, the tool's output without the fields added in this release is byte-identical to
the output of the release before (golden files in
`Examples/Solid3D/Tests/MartySolidCLITests/Golden`). `annotated-winch.json` is new: the
release before refuses it (`assembly.unknown.annotations`), so its golden pair holds this
release's output. The anchor checks add `anchorIssues`, `anchorUntested` and `anchor`; the only shipped document they
refused, `docs/assets/jet-suit/jet-suit.json` (label `lComb`), was fixed, so its golden files hold the fixed file's
output. Every refused report now ends with `repair` (one line, [Anchor suggestions](#anchor-suggestions) and
[REASONS.md](REASONS.md#limit-details)) and a limit refusal adds `limit`; the golden files of refused inputs hold these
two new members and nothing else changed. The arrow rule adds `arrowIssues` and `arrow`; the only shipped document it
refused, `docs/assets/jet-suit/jet-suit.json` (arrow `aTL2`: its head was behind the pack in step 2), was fixed with
the check's own suggested move, so its golden files hold the fixed file's output.

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
  inner part. The instance id alone (`stage`) means all its parts in a step `focus`,
  `highlight`, `ghost`, `hide`, `show` or `section.parts`; anywhere else it is refused
  (`ref.component.stage`). Authored ids are
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
  budget count the expanded assembly (`parts.count`, `parts.resolved`,
  `assembly.budget`). The authored `parts` array holds 1–48 entries; with the parts
  the `use` instances make it may hold up to 96 wire parts (`MGSolidLimits.expandedParts`;
  `parts.count` above it), and at most 96 parts after `repeat` (`parts.resolved`).
  A `parts.resolved` report adds `limit`: `{"count", "limit": 96, "top", "field": "parts",
  "actual", "unit": "parts"}`, where `top`
  lists up to 5 `use` instances with the most resolved parts (`{"id", "use", "parts"}`,
  most parts first, ties by id), so a model sees which components to drop or shrink.
  Every other limit refusal reports `limit` too ([REASONS.md](REASONS.md#limit-details)).
* **Step lists.** A step's `focus`, `highlight`, `ghost`, `hide`, `show` and
  `section.parts` hold at most 16 entries as authored (`step.focus`, `step.highlight`,
  `step.ghost`, `step.hide`, `step.show`, `step.section.parts`): **an instance id is one
  entry**. Then anchors resolve, instance ids expand to their wire part ids and
  duplicates merge; the expanded list is not limited to 16 (it is bounded by the 96
  resolved parts). So five `microTurbojet` instances (11 parts each) in one `highlight`
  are 5 entries that light 55 parts. A repeated part's base id then expands to all its
  copies, as in any document.
* **`explode` (v2).** A top-level `use` entry in a v2 assembly may take `explode` (three
  coordinates in mm, in the instance's parent frame, like a part's `explode`): it is
  added to the explode of every root part of the instance (the parts without a
  `parent` inside it), so the whole instance moves out together at full explode. Inner
  parts ride on their roots and keep their own explode, and each root keeps its own
  `explodeWindow`. Refusals: `component.use.explode` (not three coordinates in
  -4000...4000, also after the sum), `component.use.unknown.explode` in v1.

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
`integer` and `about`), `constraints` (32), `anchors` (8; name → inner id),
`anchorAbout` (anchor name → one line of plain text, 1–120 scalars, saying where the
anchor's frame sits and how its axes point; every key must be an anchor, else
`component.anchorAbout`)
and `checks` (8). References inside a component name its own parts only
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
ids, anchors and `anchorAbout` when a component has it), about 7.6 KB for the
built-ins, so a model can discover them cheaply. A model reads only the catalog, so a
frame that a part should touch (the mannequin's `back`) is described there.

| Component | Parts | Key parameters (defaults) | Anchors |
| --- | --- | --- | --- |
| `spurPair` | pinion, wheel | pinionTeeth 12, wheelTeeth 36, module 2, width 10 | input pinion, output wheel |
| `planetaryStage` | sun, ring, carrier, planet × N | sunTeeth 24, planetTeeth 18, planets 3, module 2, width 12 | input sun, output carrier |
| `sliderCrank` | frame, crank, piston, rod | radius 18, rod 62, piston 14 (stroke = 2 × radius) | input crank, output piston |
| `propeller` | hub, blade × N | blades 3, span 110, chord 34, pitch −40, twist 28, hub 12 | input hub |
| `housingBase` | base, bolt × N | radius 84, thickness 7.5, bore 8, bolts 6 (top face at z = 0) | frame base |
| `shaftWithBearing` | shaft, lowerBearing, upperBearing | radius 6, length 80, bearingWidth 12 | input shaft |
| `fanStage` | hub, rotor (blade row), casing | blades 18, root 60, span 90, chord 40, stagger 35, twist 15 | input hub |
| `mannequin` | body, skull, upperArmL/R, lowerArmL/R, handL/R, legL/R, footL/R | leftShoulder 10, rightShoulder 10, leftElbow 15, rightElbow 15 (degrees) | back, head, leftShoulder, rightShoulder, leftHand, rightHand, leftFoot, rightFoot |
| `centrifugalCompressor` | impeller, vane × N, splitter × N, diffuser, diffuserVane × M | diameter 100, vanes 7, diffuserVanes 12, bore 4 | input impeller, frame diffuser |
| `microTurbojet` | intakeLip, impeller, diffuser, combustor, nozzleGuideVanes, turbineWheel, nozzle, shaft, frontBearing, rearBearing, casing | diameter 110, length 280, cutaway 0 | intake, exhaust, mount, input shaft, compressor impeller, turbine turbineWheel |

### Figure and compressor components

**`mannequin`** is a smooth, clearly schematic adult figure, 1.75 m tall (a fixed
size, so it also gives the scale of a machine beside it). It is built from revolved
profiles: an egg-shaped head with a small nose, a chest, a shoulder bar, a waist and a
pelvis bar, ball shoulders, elbows, hips and knees, tapered limbs, mitten hands and
feet. It stands with its soles at z = 0 and faces −Y; its left side is +X. Each
shoulder and elbow is a `revolute` joint held still by a zero-scale drive
(`{"input": 0}`, read back as "held still"), turned to the angle in its parameter:
`leftShoulder` / `rightShoulder` raise the arm out to the side (4–170°, degrees from
hanging) and `leftElbow` / `rightElbow` bend the forearm forward (0–150°). Anchors
name parts whose frames sit at useful points, so other parts can hang on them with
`parent` and a short `at`. The catalog's `anchorAbout` gives each frame in one line:

| Anchor | Part | Frame origin | Axes |
| --- | --- | --- | --- |
| `back` | `body` | centre of the upper back surface, (0, 125, 1340) | world axes |
| `head` | `skull` | centre of the head, (0, 0, 1652) | world axes |
| `leftShoulder`, `rightShoulder` | `upperArmL`, `upperArmR` | shoulder joint, (±205, 0, 1430) | turn with the arm; local −Z runs down the upper arm |
| `leftHand`, `rightHand` | `handL`, `handR` | wrist | local −Z runs along the hand, +Z up the forearm |
| `leftFoot`, `rightFoot` | `footL`, `footR` | centre of the sole, (±95, 0, 0) | world axes |

```json
{"id": "pilot", "use": "mannequin", "with": {"leftShoulder": 30, "rightShoulder": 30, "leftElbow": 10}},
{"id": "jet", "parent": "pilot.rightHand", "at": [-85, -62, 0], "shape": {"shaft": {"radius": 50, "length": 300, "z0": -80}}},
{"id": "pack", "parent": "pilot.back", "at": [0, 30, 0], "shape": {"box": {"size": [260, 60, 380]}}}
```

The `back` frame's origin is on the torso surface, so a back pack touches the body when its
shape starts at local y = 0 and runs out along +Y (above: a box 60 mm deep, centred 30 mm
out). An `at` of `[0, 110, 0]` for the same box leaves an 80 mm gap. A test places this
pack and checks that the gap to the torso is under 1 mm. There is no `chest` anchor: the
component already has the most anchors a component may have (8), and the chest surface
has no part frame of its own.

The figure has 12 parts and exactly 26,048 triangles at every parameter value (under
2 % of the mesh budget). It has no `checks`: the ranges were chosen so that the arms
clear the body at the range corners (worked out by hand from the shapes; the engine does
not test parts against each other for collisions), and the tests run all 16 range corners
through `check --strict` (no warning). It is not an anatomical model: proportions are
those of an artist's mannequin, the joints only turn as listed, and legs, neck and
hands do not move.

**`centrifugalCompressor`** is one radial compressor stage, as in a small gas turbine
or a turbocharger: the `impeller` (input; a hub that curves from the eye at −Z out to a
backing disc at the tip diameter, turning about +Z) carries `vanes` backswept main
vanes and as many shorter `splitter` vanes half a pitch ahead of them; a fixed
`diffuser` ring around the tip carries `diffuserVanes` wedge vanes leaned with the
swirl. Air enters at −Z through the eye and leaves outward. Parameters: `diameter`
(impeller tip diameter, 30–1000 mm), `vanes` (4–12), `diffuserVanes` (6–12) and `bore`
(shaft hole radius). The check `bore` refuses `bore ≥ 0.075 × diameter`
(`component.check.bore`), so the hole stays inside the hub. Every size is a fixed
fraction of `diameter`: the impeller is 0.40 × diameter long, the diffuser vanes run
from 0.545 to 0.765 × diameter in radius and the ring ends at 0.80 × diameter. At the
defaults it has 28 parts and 5,996 triangles; at 12 + 12 + 12 vanes, 38 parts. Parts
stay countable for `repeat` (at most 12 copies each).

```json
{"id": "comp", "use": "centrifugalCompressor", "parent": "starter", "at": [0, 0, 262],
 "with": {"diameter": 270, "vanes": 7, "diffuserVanes": 11, "bore": 19}}
```

A step may highlight, ghost, hide or cut the whole stage with its instance id
(`"highlight": ["comp"]`, `"ghost": ["comp"]`; one entry each). The shapes are schematic: the
vanes are flat-topped extrusions in three height steps rather than a curved shroud
line, and no air flow, pressure or speed is computed.

**`microTurbojet`** is one complete small gas-turbine jet engine of the JetCat class,
schematic and ready for a cutaway, so a model can show the inside of a jet engine with
one `use`. The axis is +Z: air enters at z = 0 and leaves at z = `length`. The parts,
in airflow order: `intakeLip` (a bell-mouth ring), `impeller` (the centrifugal
compressor: the hub profile of `centrifugalCompressor` at 0.62 × `diameter` with seven
radial vanes in one blade row), `diffuser` (a vaned diffuser ring and the shaft tunnel
that holds the bearings), `combustor` (an **annular** combustor: outer liner, inner
liner and a front dome, one ring, not a can), `nozzleGuideVanes` and `turbineWheel`
(one axial turbine stage: 13 guide vanes, a disc with 23 blades), `nozzle` (exhaust
cone and tail cone), `shaft`, `frontBearing`, `rearBearing` and the `casing`.
Parameters: `diameter` (casing outer diameter, 60–300 mm), `length` (intake to nozzle
exit, 120–900 mm) and `cutaway` (0 or 1; 1 leaves a 90° window in the casing between
+X and −Y, with capped faces, to show the inside without a section step). Radial sizes
are fixed fractions of `diameter`, axial positions fixed fractions of `length`.

Anchors (the catalog's `anchorAbout` gives each frame): `intake` (centre of the intake
plane, z = 0), `exhaust` (centre of the nozzle exit, z = `length`, +Z is the jet
direction), `mount` (the axis at mid-length), `input` (the shaft), `compressor` and
`turbine`. The shaft, the impeller and the turbine wheel each turn about +Z with
`{"input": 1}`, so they turn together, one turn per input turn, and their `speed` facts
are **Solved** (`jet.shaft.speed`, `jet.compressor.speed`, `jet.turbine.speed` are 1).
**Thrust, flow, pressure, temperature and fuel are not modelled**: the engine computes
no force for this component, and the catalog's `about` says so.

Checks (only what holds for the geometry): `bore` (the shaft radius, 0.04 × diameter,
stays below 0.075 × the compressor diameter, the hub rule of `centrifugalCompressor`)
and `fits` (the compressor stage, to the end of the front bearing at
0.1 × length + 0.26 × diameter, ends before the combustor at 0.38 × length;
`component.check.fits`, so `length` must be at least about 0.93 × `diameter`). Every
part is a closed mesh, so a step `section` can cut any of them. At the defaults it has
11 parts and 18,796 triangles (18,608 with `cutaway`). Five engines, a mannequin and a
back pack are 68 parts: inside the 96-part limits (a test checks exactly that document
with `check --strict`). The tests run all eight parameter corners through
`check --strict`: six pass with no warning, and the two corners with diameter 300 and
length 120 are refused with `component.check.fits`.

```json
{"id": "back", "use": "microTurbojet", "with": {"diameter": 110, "length": 280},
 "parent": "pack", "at": [0, 95, 140], "rot": [1, 0, 0, 180]}
```

The shapes are schematic: straight radial vanes, flat liners, no cooling holes, no fuel
system, no starter.

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

## Rendering: camera framing and the loop

`MGSolidRenderPlan` lists what `marty-solid render` takes: `hero.png`, `exploded.png`,
one captioned still per step, and the loop frames. `cameras(_:width:height:)` gives the
camera of each shot from one rule (`MGSolidFraming`, Foundation only, deterministic);
the tool and any host use the same cameras.

* **Focus.** A step first frames its focus from its own camera preset and `orbit` (this
  first framing keeps the direction; only the target and distance change). The
  unblocked-focus rule below may then draw blocking parts as ghosts or, when a part of
  the focus context hides much of the focus or a section faces away, choose one of four
  fixed other directions. The focus is the step's
  `focus` list as written, or else its `highlight` and section parts **plus every part
  the step does not ghost whose posed box touches one of them** (one level, within
  0.5 % of the model's box diagonal), plus the anchors of the annotations the step
  shows. So a gear inside a gearbox brings its housing and the mechanism stays whole,
  while a cutaway that stands apart is framed on its own. The focus fills 88 %
  (`MGSolidFraming.fill`) of the safe window, centred in it. An inferred focus (highlight
  and section parts with their context) whose box is more than 75 % of the whole model's
  box diagonal (`focusShare`) uses the whole-model rule. A `focus` list is always framed
  exactly, however large: to frame a part exactly, list it in `focus`.
* **Whole model.** Other stills keep the bounding-sphere framing of earlier releases
  unless a part or an annotation anchor would leave the image or enter the caption
  band; only then is the still fitted like a focus. Earlier stills could reach into the
  title band; a fitted still keeps it free too. **`hero.png`** keeps the title band free
  always: its earlier framing stays only when the model and its annotation anchors clear
  the title band as well, otherwise it is fitted (`modelFitted`), so the model never
  sits under the title. Parts the view hides are left out of every rule.
* **Safe window.** The image minus the caption band (stills with a caption) and minus
  the title band (stills with a title). `MGSolidRenderPlan.bands(width:height:)` gives
  them as fractions of the height: the bands the tool draws (120 and 100 px at
  1280 px wide, scaled with the width), but at least the bands the annotation layout
  keeps free (0.2 and 0.14). The caption band never covers the model.
* **Loop.** Loop frames keep the earlier per-frame framing. When any frame would cut
  the model, every frame moves back by the same factor (to 94 % of the frame), so the
  orbit never jumps. The manifest records the factor as `framingScale`.
* **Points.** The fit reads the posed mesh vertices, not box corners, so round parts
  are not framed by their corners. Over 200,000 vertices (`pointBudget`) each part is
  sampled with a stride plus its extreme vertices along 26 directions.
* The renderer's far plane reaches the farthest corner of the posed model, so a close
  focus never cuts the rest of the scene at the back. The near plane sits at
  `MGSolidFraming.nearPlane(distance:)`, the larger of 0.5 mm and 5 % of the camera
  distance; the fit keeps every framed point at least 10 % beyond it, so a
  sub-millimetre focus moves the camera back instead of being cut. Parts outside the
  focus that come nearer than the near plane are cut.

A host that shows one step calls
`renderer.frame(MGSolidShot.step(document, i)!, document: document, aspect: w / h)`
(`titleBand: 0, captionBand: 0` when it draws no title or caption over the view), or
reads `MGSolidFraming.framing(_:shot:aspect:…)`, which also returns the rule that chose
the camera (`focus`, `model`, `modelFitted`). `marty-solid render` writes that rule as
`framing` in each still's manifest record.

### Title backdrop

Every still and every story frame draws a dark backdrop behind the title band: black at
88 % opacity over the band (100 px at 1280 px wide, scaled with the width), then a soft
fade to clear over 28 px below it, the same kind of protection the caption band has.
It lies under all text of the band (the title, the legend line and the overlay's legend
corner), so geometry outside the focus that reaches into the band never washes the text
out: a test renders a bright white wall through the band and measures at least 4.5:1
contrast for the title and the legend line (and the same over a pure white image). The
overlay's legend corner scales with the frame height, so in a tall frame it reaches below
the band: its whole rectangle gets the same backdrop and fade. An explainer's board line
(a beat whose board shows only text) gets its own backdrop behind the line's text bounds,
because in a tall frame it can reach into the 3D pane. Tests check 4.5:1 for the legend
corner and the board line at 1280×800, 800×1280, 1280×1280 and 640×1280. In an explainer
the band lies over the dark frame background, above the panes. Loop frames draw no title
or legend text and get no backdrop.

Text readability is guaranteed (every interior stroke row of every glyph of the title, the
legend line, the legend corner, the board line and the caption at least 4.5:1, also over a
pure white render) for frames at least 1280 px wide and 720 px tall, up to 3840 px wide,
with an aspect ratio (width ÷ height) from 0.5 to 2.0. The compositor test covers frames up
to 1280×2560 and 1600×3200, but `marty-solid render --size` accepts heights only up to 2160
(widths 320–3840). So the CLI cannot render an aspect of 0.5 inside the guarantee (1080×2160
is narrower than 1280 px); its tallest guaranteed frame is 1280×2160 (aspect about 0.59). The caption band uses 84 % black,
the title band and its legend corner 88 %, the legend line is medium weight at 85 % ink,
and the explainer board line is semibold in full ink. Smaller frames are still rendered,
but their smallest text falls below about 10 px and is not guaranteed to meet 4.5:1;
render at the default 1280 × 800 or larger for public stills. The CLI test `testEveryTextLineInTheGuaranteedRange` checks each
text line row by row over pure white across this range; the per-glyph criterion was
checked by an independent audit.

### Unblocked focus

A step framed on its focus (`framing: focus`) is then checked for parts that hide the
focus from the camera (`MGSolidFraming.clearView`, Foundation only, deterministic). The
render plan's stills (`MGSolidRenderPlan.cameras`, field `clear`), each explainer beat's
solid pane (`MGExplainerFrame.solidClearView`; `solidCamera` returns its camera) and the
hold frames of `story.mp4` use this one function.

1. **Samples.** At most 48 (`occlusionSamples`) triangle centroids of the focus parts
   (a cut part gives its capped cut mesh), split evenly over the parts by a fixed
   stride, at the shot's pose.
2. **Rays.** A segment runs from the camera to each sample. A part hides the sample
   when its triangles cross the segment before the first focus surface on it. Only
   parts the view shows at opacity 0.5 or more hide samples. The **focus group** never
   does: the focus parts, the parts attached below them (`parent` chain) and the parts
   whose posed box lies inside the focus parts' box (the inside of a cutaway). A part
   does not hide a sample that lies inside it (an odd number of crossings of its
   surface up to the sample, like a pin in its hole): no direction would show it. The
   ray test is watertight (Woop, Benthin and Wald 2013) with a half-open tie rule, so a
   ray through an edge or a vertex shared by two or more triangles counts once. Each
   view direction may spend 3,000,000 triangle tests (`occlusionTests`); samples after
   that are not tested.
3. **Automatic ghosts.** Every part outside the focus context that hides more than 5 %
   (`ghostShare`) of the samples is drawn at the ghost opacity (0.2) in that still and
   its story beat only (`autoGhost`, assembly order). The focus context is the focus
   group, plus, for a step with an explicit `focus` list, the parts whose posed box
   touches a focus part (the touch rule of the focus framing). The honesty legend does
   not change.
4. **Keep the author's direction.** The step's own direction (preset and `orbit`) stays
   while at most 30 % (`keepShare`) of the samples stay hidden after the ghosts and, when
   the step's `section` cuts a focus-group part, the view **faces the cut** (`facesCut`):
   the camera on the cut-away side of the first such part's plane (assembly order),
   looking within about 75° of its normal (`cutFacing`, cosine 0.25), so the cut face is
   seen and not the outside of the kept half. (An authored cutaway, such as the turbofan's
   open casings, may hide part of the far side of its inner parts; that alone does not
   turn the camera.)
5. **Other directions.** Otherwise (a context part hides much of the focus, or the view
   faces away from the cut) a fixed list is tried in order, each framed on the same focus
   with its own automatic ghosts: `opposite` (yaw + 180°), `quarterLeft` (yaw + 90°),
   `quarterRight` (yaw − 90°), `raised` (pitch 60°, or 10° when the preset looks down
   from 45° or more). The first that is **clear** (at most 10 % hidden, `clearShare`) and
   faces the cut is taken; else the first clear one (the step's own direction first);
   else the step's own direction stays.

`marty-solid render` writes the result in each step still's and explainer beat still's
manifest record and in the story's beat record: `autoGhost` (ids), `occluded` (the share
of samples still hidden), `focusSamples`, `view` (`preset` or the alternative taken) and
`facesCut` (section steps). The record's `offView` counts the shown annotations whose
anchor is outside the view **plus** the focus samples still hidden, so a focus hidden
behind another part no longer reports 0; it is written when the image draws annotations
or has a tested focus. Example: a cutaway of an engine mounted on a mannequin's back,
seen from the front through the figure's neck and shoulder, now looks from behind at
the cut face (`view: opposite`, `occluded: 0`).

**Not checked.** The rule tests only steps framed on their focus. A part may still hide
the focus when every direction is blocked by the focus context (the record then shows
the hidden share). Parts outside the focus may be cut at the image edge,
and may lie under the caption band or the legend (for example the feet of a figure
whose arms are the focus); only the focus and the step's annotation anchors are kept
inside the safe window.
The fit keeps the posed geometry and annotation anchors inside the window, not
annotation text, shadows or exhaust glow.

**Loop video.** `marty-solid render` also writes `loop.mp4`: H.264 (AVFoundation, no
other software), at the still size (default 1280 × 800; an odd width or height is
written one pixel smaller), with every loop frame the engine rendered at its exact time
(frame k at k / rate seconds; the file lasts frames / rate seconds). The default rate
is 10 frames per second: 120 frames, the same frames as `loop.gif` at full size.
`--loop-fps 30` renders 360 real frames over the same 12 seconds for the MP4; the GIF
keeps every third frame (the same poses as at 10). No frame is interpolated. The
manifest record gives `codec`, `width`, `height`, `frames`, `fps`, `loopSeconds` and
`framingScale`. If the encoder fails or stops (a full disk, a cancel) or takes no frame for
60 seconds, the render stops with an error and removes its output directory, so no
manifest names a partial MP4. The poses and cameras are deterministic; the rendered pixels and the H.264 bytes are not byte-identical
between runs (GPU rendering and the hardware encoder).

**Story video.** `marty-solid render` also writes `story.mp4` for an assembly with steps
and for an explainer with beats: the steps (or beats) in order, each with its caption,
its view (section cuts, ghosts), its highlight, its annotations and its framed camera,
and the legend in every frame. An assembly with annotations draws the document legend
and its notes ("Arrow lengths are not to scale") in the overlay corner of every frame,
also while labels are hidden; an assembly without annotations shows the legend at the
start of the footer line. An explainer's footer is the same legend line, with its notes,
as its stills. The plan is
`MGStoryPlan` (Foundation only, deterministic); the rules are `MGStoryTiming`:

| Rule | Value |
| --- | --- |
| Hold of one beat | reading time = 1 s + caption Unicode scalars / 15, or the spin time if longer, bounded to 3–9 s |
| Spin | a step's `spin` plays at 4 s per input turn from the beat's first frame (faster when that would take more than 9 s, so it always ends within the beat; the spin time is clamped to 9 s before it becomes a frame count, the sign is the turn direction, and a spin that is not finite counts as none); the rest of the beat holds the end pose. A step without `spin` holds still (so every shown dimension keeps the value its step was checked at) |
| Camera | during a beat's hold the camera is exactly the camera of the beat's still, for the same layout (`MGStoryPlan.camera(frame:beatCameras:)`); in an explainer the solid pane is fitted for its own pixels in that beat's layout, full frame or split (`MGExplainerFrame.solidCamera`) |
| Camera move | from the previous beat's camera to this beat's camera over the first 0.6 s of the beat (`transitionSeconds`; at most half the beat), eased in and out: target and field of view in a straight line, yaw the shorter way round, pitch linearly, distance geometrically. When that straight move would pass through a part, a routed path is taken instead (pull back, arc, or both; [Routed moves](#routed-moves) below); a routed move takes 1.0 s (`routedTransitionSeconds`; at most half the beat), and only when no path is clear does the beat cut. During the move the caption band is empty and no label is drawn (3D arrows and dimensions stay, with the legend and its notes); in an explainer the board still shows the previous beat's state. The beat's caption, labels and board claims appear on the first frame of its hold (`MGStoryPlan.holds(frame:cuts:)`, `caption(frame:cuts:)`, `holdStartFrame`). The first beat starts at its own camera. In an explainer, a beat whose solid pane has another size than the previous beat's (the board pane appears or goes) cuts to its own camera instead of moving, because the previous camera was fitted for the other pane |
| Rate and size | 30 frames per second by default (`--story-fps 10` or `30`), at the still size (default 1280 × 800) |
| Length | at most 3,600 frames (2 minutes at 30 fps); a longer story is refused with `story.frames` before any file is written (`--no-story` renders without it) |

Every frame is a real render at its pose and camera. Only the camera, and the placements of
a step `pose`, are in between two beats: during the camera move into a beat the parts that
either beat poses move from the previous beat's placements to this beat's with the same
eased blend as the camera (`MGStoryPlan.placements`), and the hold shows the beat's own pose.
The view (cuts, ghosts, hidden and shown parts), the highlight and the input and explode
change at the beat's first frame, with one exception during the camera move: a part that the
previous beat draws as a ghost (a step `ghost` or an automatic ghost; drawn fainter than the
part's own opacity) is also drawn as a ghost during the move into the next beat
(`MGSolidView.moving(from:_:)`), so a camera that leaves a close-up through a ghosted body
does not start inside a solid one; it turns solid when the hold starts. The
caption, the labels and (in an explainer) the board's new state appear when the hold
starts, so a caption never names something the camera has not reached yet, and a
caption with a number shows only while its own beat's state is on screen at the beat's
own camera. The board shows the beat's settled state, the same state as the beat's still.
The last frame of each beat has the same pose and camera as that beat's still. Labels
keep their places for the rest of the beat. The writer is the one
`loop.mp4` uses: a pool per frame, the same failure handling (fail fast, a 60-second
stall timeout, the output directory removed). The manifest record gives `codec`,
`width`, `height`, `fps`, `frames`, `seconds`, `transitionSeconds`, `routedTransitionSeconds`,
`holdSeconds` (`min`, `max`) and per beat `{"beat", "start", "holdStart", "seconds", "camera",
"offView", "cut", "cutReason", "path", "pathReason", "blockedBy", "moveSeconds"}` (start time,
the time the caption, labels and claims appear, and
length in seconds, the hold camera, the number of shown annotations whose anchor is
outside the view in the beat's last frame plus the focus samples still hidden (absent
when the beat shows no annotation and has no tested focus), whether the beat cut
instead of moving, and why: `layout` or `blocked`; for each beat with a tested move,
its path `straight`, `pullback`, `arc`, `combined` or `cut`, why (`clear`, `blocked`,
`layout`, `motion`, or `untested` for a camera that is not finite), the first part the straight
move meets (`blockedBy`, for `blocked`) and the move's length in seconds, 0 for a cut;
the first beat has no move), plus the unblocked-focus fields
`autoGhost`, `occluded`, `focusSamples`, `view` and `facesCut` for a tested focus. Each step still's record (`step-<n>.png`) and each explainer beat still's
record (`beat-<n>.png`) give the same `camera` and `offView`, so a host can check that
the story holds on the still's framing.

### Routed moves

`MGStoryPlan.routes` gives each beat's camera move (`MGStoryMove`). For each beat after the first whose camera and
the previous beat's camera are known, paths are tried in a fixed order, and the first clear one is taken:

1. `straight`: the move above.
2. `pullback`, for each pull-back distance `D` in ascending order (1.5, 2, 3 and 4 times the start camera's distance,
   `pullbackFactors`, and the distance at which the start camera leaves the model's bounding sphere grown by the
   clearance, when that is at most 8 times the start distance): the camera moves straight out along its view to `D`
   (same target, yaw, pitch and field of view), then moves to the end camera.
3. `arc`, for each radius `R`: from the start camera to a key camera that looks at the model's bounds centre from the
   start camera's direction at distance `R`; an orbit about that centre at distance `R` (yaw the shorter way, pitch
   linearly, pitch limited to ±85°) to the end camera's direction; then to the end camera. The radii are `r0 + c`,
   `1.25 × max(r0, ρ) + c` and `1.75 × max(r0, ρ) + c` (`arcFactors`), where `r0` is the larger of the two cameras'
   distances from the centre, `ρ` the bounding sphere's radius (half the bounds diagonal) and `c = 0.1 ρ`
   (`routeClearance`). So the orbit is never closer to the centre than either camera.
4. `combined`, for each pull back and then each radius: the pull back, then the arc from there.

At most 24 paths per move (`maxRouteCandidates`). Each path is a chain of key cameras, each leg played with the move's
own interpolation (`MGStoryPlan.camera(from:to:_:)`); the legs share the move's eased time by their weight (camera path
length plus target travel plus turn times mean distance), so the camera keeps about one pace. A path starts exactly at
the previous beat's camera and ends exactly at this beat's camera, so the hold cameras are always the stills' cameras.

**The test.** A path is clear when no leg meets a part box. Each leg is split into straight chords of the played path
as above (at most 1,024, `maxMoveChords`, with the proven chord error from the curvature bound), and also so that the
camera distance changes by at most 10 % per chord (`routeDistanceStep`). Each chord is tested with the exact
segment-versus-box slab test against each blocking part's swept box (render frame), grown by the renderer's near
plane at the larger camera distance of that chord's two ends plus the leg's chord error.

**Parts that move during the move.** The frames of a move show the parts moving: the beat's spin plays from its first
frame, and the placements of a step `pose` blend from the previous beat's (`MGStoryPlan.movePose`, the pose the render
tool draws each move frame with). A part's swept box is the union of its world boxes at the previous beat's end pose,
at every frame of the move as the story plays it, and at this beat's end pose, grown by the largest distance any
corner of its mesh box moves between two of those poses in a row (`MGStoryPlan.sweptBoxes`). The straight path is
tested with the frames of a 0.6 s move, a routed path with those of a 1.0 s move. A part that does not move keeps its
one box. When the frames are not known (`routes` without a `plan`) and the parts move, or a swept box is not finite,
the beat cuts with reason `motion`. So a part that crosses the camera's path between the two beat poses blocks that
path, and a route that was clear only because a part was elsewhere at both ends is refused (it routes around the
swept box, or cuts). The blocking parts are the parts the move draws solid: the parts that the move's view (the beat's
view with its automatic ghosts, plus the previous beat's ghosts) does not hide and draws with a coverage of
`MGSolidFraming.blockingOpacity` (0.5) or more, the coverage rule of the anchor checks (view opacity times
`MGMaterialPreset.coverage`, so a ghost and glass do not block). The bounds centre and sphere are those of the
blocking boxes. The straight path is tested the same way; it is clear where the earlier rule
(`MGStoryPlan.blockedMoves`, still in the library: every part, and one growth for the whole move, the near plane at the
larger camera distance) cut a move that passes a part at a close camera's own near-plane distance.

A beat whose move has no clear path cuts (`cut`, reason `blocked`, `blockedBy` the first part the straight move meets);
a beat whose solid pane changed size cuts with reason `layout` without a test. The path test is deterministic; at most
24 paths of at most 4 legs of 1,024 chords against 96 boxes per move, and at most 2 × (the frames of a 1.0 s move + 2)
poses per beat. Not tested: the meshes themselves (boxes only, and a swept box is the box of a whole sweep, so a path
that only passes close to a part, or through the empty middle of a sweep, may be refused), and whether the routed path
looks good: the arc and pull back keep the model in view only roughly (the camera looks along its interpolated target).

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
| `hidden` | ids of the parts the view hides ([step visibility](#hide-and-show)), in part order; their ranges hold no triangles and they are neither highlighted nor cut (absent when none) |
| `posed` | ids of the parts whose placement the exported pose changes ([step pose](#pose)), in part order; the positions are already posed (absent without a pose) |

The decoder dispatches on `format`. A `/1` file keeps exactly its v1 meaning: its bytes
are unchanged for the same assembly, and a `/1` file with any v2 field fails to decode. A
`/2` file is checked too (an opacity on every part, cap ranges inside their part, a unit
section normal, known section parts, three-number emission colours, and for annotations: finite
points, unit arrow directions, known meanings, roles and tiers, unique ids, triangle ranges after the
parts, in order and inside the list, placements of known ids, known highlight parts; `hidden` and `posed`
list known parts once each, and a hidden part has no triangles, no cap and no highlight). A `/2` export
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
