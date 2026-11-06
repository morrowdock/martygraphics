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
No rendered images are checked in yet.

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
  clipping with hole bridging otherwise.
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
* **Constraints**: `gearMesh` and `fixed`. The compiler checks modules, axes,
  centre distances and that each driven gear turns about its own centre. It
  phases every tooth so meshing gears interleave, then solves the linear
  velocity system. One input plus enough meshes and fixed parts must give a
  unique ratio for every gear joint.
* **`repeat`** copies a part N times around an axis (`planet` → `planet1…3`).
  References to the base id expand to every copy; a repeated child of a repeated
  parent pairs by index.
* **Bounds** (`MGSolidLimits`): 64 KiB, 48 wire parts, 96 resolved parts,
  8 shapes per part, 256 profile points, 128 constraints, 16 steps, teeth
  8–200 (ring 20–400), module 0.2–20 mm, lengths up to 4 m.

**Patches.** `MGSolidParser.applying(_:to:)` accepts `params`, `parts` (merge
fields by id; `null` removes a field), `constraints`, `steps` and `title`. Part
ids stay stable and unchanged shapes keep their meshes, so a what-if (hold the
carrier, free the ring) recompiles the kinematics without rebuilding geometry.
`MGSolidRenderer.setAssembly(_:)` likewise keeps nodes whose mesh did not change.

## Checks

`MGSolidChecks.gearMeshes` sweeps every gear pair over input angles and measures
2D tooth overlap in the gears' plane (`maxPenetration`) and engagement
(`minClearance`). `MGAssembly.gearResiduals` checks the tooth-ratio equations.

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

`format` is `martygraphics.solid.snapshot/1`; encode with `jsonData()`.

## Limits

* SceneKit rasterisation: soft shadow maps, screen-space ambient occlusion,
  image-based lighting from a generated environment; no ray-traced reflections.
* The section plane is a fragment discard; cut faces are not capped.
* Gear contact is checked in 2D at sampled angles, not as continuous 3D contact.
* No helical or bevel gears, belts, cams or general constraint solving beyond
  linear gear ratios and the slider-crank closed form.
