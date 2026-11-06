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

## Layers

| Layer | Files | Platform |
| --- | --- | --- |
| Geometry kernel | `Solid/MGSolidMath.swift`, `MGMesh.swift`, `MGProfile.swift`, `MGSolidBuilders.swift`, `MGGear.swift`, `MGSolidShapes.swift` | Foundation only |
| Assembly and kinematics | `Solid/MGAssembly.swift`, `MGSolidModels.swift`, `MGSolidChecks.swift` | Foundation only |
| JSON format | `Solid/MGSolidParser.swift` | Foundation only |
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
A reason is always one token without spaces: author-supplied names inside it keep
ASCII letters, digits and `_` (other characters become `_`, at most 32), so
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

* **Part library** (`shape` is one primitive or an array of up to 8, each with
  optional `at` / `rot`): `gear`, `ringGear`, `shaft`, `tube`, `box`, `hex`,
  `plate` (disc with round holes), `carrier` (hub, arms and bosses with a smooth
  union), `extrudedProfile`, `revolvedProfile` (open with poles, or `closed`
  for walls such as casings and nozzles), `blade`.
* **Materials**: `brushedSteel`, `polishedSteel`, `darkSteel`, `blackOxide`,
  `brass`, `bronze`, `aluminum`, `rubber`, `glass`, `anodized.<role>`,
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
* **Internal meshes** are swept over one tooth pitch with the real outlines; a
  ring with too few more teeth than its planet, or a planet too small for its
  ring (involute interference), is refused when teeth overlap by more than
  0.01 module (`constraint.gearMesh.interference`).
* **`repeat`** copies a part N times around an axis (`planet` → `planet1…3`).
  References to the base id expand to every copy; a repeated child of a repeated
  parent pairs by index.
* **Bounds** (`MGSolidLimits`): 64 KiB, 48 wire parts, 96 resolved parts,
  8 shapes per part, 256 profile points, 128 constraints, 16 steps, teeth
  8–200 (ring 20–400), module 0.2–20 mm, lengths up to 4 m.
* **Mesh budget**: at most 1,500,000 triangles and 1,000,000 vertices over all
  resolved parts (copies from `repeat` count), computed from the validated
  fields before any mesh is built (`MGShapeSpec.meshEstimate` gives the exact
  counts `mesh()` will produce); otherwise `assembly.budget`. At the limit the
  kernel meshes, the render meshes built while loading and the SceneKit buffers
  take roughly 200 MB, which recent iPhones and iPads hold. The planetary
  example uses 55,960 triangles (under 4%). A 256-point revolve (96 segments),
  8 per part, repeated 12 times (about 4.7 M triangles) is refused at once.

**Patches.** `MGSolidParser.applying(_:to:)` accepts `params`, `parts` (merge
fields by id; `null` removes a field), `constraints`, `steps` and `title`. Part
ids stay stable and unchanged shapes keep their meshes, so a what-if (hold the
carrier, free the ring) recompiles the kinematics without rebuilding geometry.
`MGSolidRenderer.setAssembly(_:)` likewise keeps nodes whose mesh did not change;
a material-only change restyles the node in place. A section cut gives each cut
part a private material copy, so parts that share a preset are never cut with it.

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

## Limits

* SceneKit rasterisation: soft shadow maps, screen-space ambient occlusion,
  image-based lighting from a generated environment; no ray-traced reflections.
* The section plane is a fragment discard; cut faces are not capped.
* Gear contact is checked in 2D at sampled angles, not as continuous 3D contact.
* No helical or bevel gears, belts, cams or general constraint solving beyond
  linear gear ratios and the slider-crank closed form.
