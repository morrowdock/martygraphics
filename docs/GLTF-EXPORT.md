# glTF export for offline renders

MartyGraphics proves the mechanism; another renderer may make it look better. The glTF exporter writes a checked
solid scene and its motion as glTF 2.0 binary (`.glb`) with a sidecar manifest, so a film-quality renderer such as
Blender Cycles can render the same motion on another machine.

**The render is cosmetic. The proof stays in MartyGraphics.** The exporter runs only after the strict check
(`marty-solid check --strict`) passes, and it writes what the engine computed. A renderer that reads the file
re-checks nothing about the mechanism: the ratios, meshes, clearances and honesty data are in the check report of
the source document, not in the `.glb`.

## Commands

```sh
# Any assembly document: the loop of `marty-solid render` (12 s: one input turn, one orbit, explode and reassemble).
swift run --package-path Examples/Solid3D marty-solid export-gltf FILE.json NEW_DIR --engine-commit SHA [--fps 10|30] [--size WxH]

# The turbofan and its showcase loop (LP spool one turn, HP spool three turns, the slow orbit swing, 12 s).
swift run --package-path Examples/Turbofan marty-turbofan --export-gltf NEW_DIR --engine-commit SHA [--fps 30]
```

`--engine-commit` is required: the engine does not know its own git commit, so name the full 40-hex-digit commit you
built. The default frame rate is 30 fps (`marty-solid` takes 10 or 30, the render plan's loop rates; `marty-turbofan`
takes 1 to 240). `--size` sets the frame the cameras are framed for (default 1280×800). Each command writes
`<name>.glb` and `<name>.manifest.json` into a NEW directory. A document that the strict check refuses prints its
report (exit 1) and creates no directory. Explainer and lesson documents are `kind.unsupported`. In code, use
`MGSolidGLTF.check(data:)`, then `MGSolidGLTF.renderLoop(_:)` or your own `MGSolidGLTF.Timeline`, then
`MGSolidGLTF.export(...)` (library `MartySolidGLTF` in `Examples/Solid3D`).

## What the file holds

- **Nodes.** A root node `martygraphics.scene`, then one node per part, named by part id, in the assembly's parent
  hierarchy. Each part's mesh is in the part's own frame (positions and normals, 32-bit indices). A part the plain view
  hides has a node and no mesh.
- **Units and axes.** Metres (the engine's millimetres × 0.001), +Y up, right-handed, as glTF requires. The engine's
  Z-up kernel frame goes through `MGSolidStage.zUpToYUp`, as in every MartyGraphics render.
- **Motion.** Exactly one animation. Every node that moves gets one translation key and one rotation key per frame, at
  t = k / fps from t = 0, with `LINEAR` interpolation (spherical for rotations), for the whole timeline. The keys are
  the engine's own `MGAssembly.pose` at each frame: there are no joints, drives or constraints in the file. A scene
  where nothing moves keys the root node, so the animation still spans every frame.
- **Cameras.** The animated loop camera `camera.loop` first, then still cameras (`camera.hero`, `camera.exploded`,
  `camera.step-<n>` for `marty-solid`; `camera.hero` and `camera.labelled` for the turbofan), with the engine's field
  of view and the frame's aspect.
- **Lights.** The studio's three directional lights (`light.key`, `light.fill`, `light.rim`) as `KHR_lights_punctual`.
  The intensity in lux is the studio intensity × 0.683, so Blender's importer (standard lighting mode) gives the key
  light strength 1.45. The studio environment is not in the file (glTF has no portable environment light); the
  manifest records its values.
- **Materials.** Simple PBR factors: linear base colour, metallic, roughness; clear coat
  (`KHR_materials_clearcoat`), transmission and IOR (`KHR_materials_transmission`, `KHR_materials_ior`) and emission
  (`KHR_materials_emissive_strength`) where the preset has them; part opacity as alpha blending.

## The manifest

The manifest is the export format of the Blender render path, `martygraphics.render-export/1`
(`tools/render-blender/README.md`, "Export manifest"). Its fields: `format`, `engine` (`name`, `commit`, plus the
engine identity and, from the CLI, `executableSHA256`), `scene` (`id`, `title`), `glb` (`file`, `bytes`, `sha256`),
`fps`, `frameCount`, `parts` (`name` is the node name, the part id; `label` is the part name; `node`, `parent`,
`moving`, `hidden`, `triangles`, `gltfMaterial`), `cameras` (`name` is the camera's node name), and provenance that the
render path ignores: `source` (lines, bytes, SHA-256), `check` (`strict`), `units`, `upAxis`, `seconds`, `timeline`,
`lights`, `environment`, `limits` and `note`. The `parts[].material` key is left free for a render path's look-dev
override.

## Guarantees and their tests

`Examples/Solid3D/Tests/MartySolidGLTFTests` exports the AI-written robot-joint gearbox
(`docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json`), re-reads the `.glb` with an independent reader and
checks, for 5 sampled frames of 360, that every part node's world transform equals the engine's
`MGSolidStage.zUpToYUp * pose.world` within 1e-5 m and 1e-5 rad, and that the loop camera sits at the plan's camera.
Two exports of the same document are byte-identical (the manifest too). The published refused first try and a document
that only the strict profile refuses (`joint.idle.<id>`) never reach the exporter.

Refusals (`MGSolidGLTF.Refusal`): `gltf.fps` (a frame rate outside the allowed rates), `gltf.size`, `gltf.frames` (no
frame, or more than 14 400), `gltf.cameras` (an animated camera without one camera per frame), `gltf.aspect`,
`gltf.sourceID` (not a short identifier: a letter or digit, then up to 63 letters, digits, `.`, `_` or `-`),
`gltf.name`, `gltf.engineCommit` (not 40 lowercase hex digits), `gltf.nodeName` (a node name that is not unique or is
longer than 63 bytes, Blender's object-name limit) and `gltf.transform` (a part transform that is not rigid).

## Limits

- No textures, no UV coordinates, no labels, arrows, dimensions or captions, and no step views (section cuts, ghosts,
  highlights): the export is the plain scene, as the loop shows it.
- Materials are the simple factors above; a renderer's look-dev may replace them. That changes the look, never the
  motion or the geometry.
- Linear keys at the export frame rate: render at that frame rate (in Blender, set the scene frame rate before the
  import, so keys land on whole frames).
- USD/USDZ is not written. glTF is the format Blender imports animation from reliably; a SceneKit USD export was not
  built or tested.
- The exporter is outside the engine library (`Examples/Solid3D`, target `MartySolidGLTF`). It uses only public engine
  API and changes no engine output: validation, layout, framing, renders and the existing goldens are unchanged.
