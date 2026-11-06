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
| Snapshot export | `Solid/MGSolidSnapshot.swift`, `MGMaterial.swift` | Foundation only |
| Studio renderer | `Solid/MGSolidRenderer.swift` | SceneKit, CoreGraphics, Metal |

Kernel space is millimetres with **+Z up** (gear axes along Z). The render world
and the snapshot are **Y-up** (`MGSolidStage.zUpToYUp`).

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
  `chamferedBox`, `hexPrism`, `blade` (NACA 4-digit style section, linear twist
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
  `rot` sit next to `shape`. Primitives: `gear`, `ringGear`, `shaft`, `tube`, `box`, `hex`,
  `plate` (disc with round holes), `carrier` (hub, arms and bosses with a smooth
  union), `extrudedProfile`, `revolvedProfile` (open with poles, or `closed`
  for walls such as casings and nozzles; optional `sweep` and `start` in
  degrees give a capped partial revolve for cutaways, with
  ceil(96 × sweep / 360) segments, at least 2), `blade`, `bladeRow`.
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
  8–200 (ring 20–400), module 0.2–20 mm, lengths up to 4 m.
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

**Patches.** `MGSolidParser.applying(_:to:)` accepts `params`, `parts` (merge
fields by id; `null` removes a field), `constraints`, `steps` and `title`. Part
ids stay stable and unchanged shapes keep their meshes, so a what-if (hold the
carrier, free the ring) recompiles the kinematics without rebuilding geometry.
`MGSolidRenderer.setAssembly(_:)` likewise keeps nodes whose mesh did not change;
a material-only change restyles the node in place. A section cut gives each cut
part a private material copy, so parts that share a preset are never cut with it.

## Worked examples

Small, complete models that `marty-solid check` accepts; a test keeps them valid.

* [`slider-crank.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/slider-crank.json)
  (21 lines): a crank on a `revolute` joint with an `input` drive, a piston on a
  `prismatic` joint driven by `crankSlider` (crank radius 18 mm, rod 62 mm, so a
  36 mm stroke), and a connecting rod parented to the piston and driven by
  `crankRod`, so it stays between the wrist pin and the crank pin.
* [`propeller.json`](../Examples/Solid3D/Sources/MartySolid3D/Models/propeller.json)
  (14 lines): a driven hub and one `blade` (span, chord, taper, twist, camber)
  copied three times with `repeat`, so the copies turn with the hub.
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
  and `repeat` copies `stage.planet1…3`. Constraints, drives, parents and steps refer
  to them by these ids. An anchor (`stage.input`, `stage.output`) names an inner part.
  The instance id alone (`stage`) means all its parts in a step `focus` or
  `highlight`; anywhere else it is refused (`ref.component.stage`). Authored ids never
  contain a dot.
* **`set`** changes fields of inner parts as if the component had written them, for
  example `{"set": {"pinion": {"drive": null, "material": "bronze"}}}` (`null`
  removes a field). Ids inside `set` are the outer document's ids. A compound train
  keys the second pinion to the first wheel this way:
  `{"id": "s2", "use": "spurPair", "at": [48, 0, 14], "set": {"pinion": {"parent": "s1.output", "at": [0, 0, 14], "joint": null, "drive": null}}}`.
  `at` / `rot` apply to the parts that are roots after `set`.
* **Patches.** `{"parts": {"stage": {"with": {"planets": 4}}}}` edits the `use` entry;
  `{"parts": {"stage.ring": {"material": "bronze"}}}` merges into its `set`.
* **Limits.** Nesting at most 3 levels (`component.depth`), cycles refused
  (`component.cycle.<id>`), expanded ids at most 64 characters
  (`component.id.length`). The part, constraint and step limits and the mesh budget
  count the expanded assembly (`parts.count`, `assembly.budget`).

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
| `propeller` | hub, blade × N | blades 3, span 110, chord 34, twist 30, hub 12 | input hub |
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

`MGSolidSnapshot.make(_:params:camera:aspect:lighting:)` exports one posed frame:

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

`format` is `martygraphics.solid.snapshot/1`; encode with `jsonData()` (an empty
assembly exports zero bounds and a unit framing camera, so the JSON stays finite).
Decoding checks every fixed-size slot (three numbers for colours, directions,
targets and bounds, eight per soft box, three floats per vertex, one normal per
vertex, indices inside the vertex list, one material per triangle, part ranges
inside the triangles) and fails instead of trapping later.

`Examples/Turbofan/Sources/MartySolidRT` maps a snapshot to an `MGRTScene` for
`MartyGraphicsPathTracer`: one mesh and instance per part, sRGB colours to linear,
metallic presets to GGX metals (base colour as F0), the rest to plastic, transmissive
presets to glass, clear coat carried over, the studio environment and soft boxes to an
environment map, and directional lights to hidden area lights. It sits in the example
so the two libraries stay independent.

## Limits

* SceneKit rasterisation: soft shadow maps, screen-space ambient occlusion,
  image-based lighting from a generated environment; no ray-traced reflections.
* The section plane is a fragment discard; cut faces are not capped.
* Gear contact is checked in 2D at sampled angles, not as continuous 3D contact.
* No helical or bevel gears, belts, cams or general constraint solving beyond
  linear gear ratios and the slider-crank closed form.
