# Blender render path for MartyGraphics explainers

Decision (owner, 2026-11-11): **verify in MartyGraphics, render in Blender.**
MartyGraphics proves the mechanism and exports the verified scene with baked
per-frame motion as glTF 2.0 (`.glb`) plus a manifest. This tool renders that
export in Blender Cycles for film-quality output. The render is cosmetic.

## Rules

1. **The render is cosmetic.** The pipeline never changes the exported motion,
   timing or geometry positions. It proves this on every run (see
   [What the checks prove](#what-the-checks-prove)) and stops when a check fails.
2. **The manifest gates the render.** Before any render, `render.py` checks the
   `.glb` SHA-256, the fps and the frame count against the manifest and refuses
   a mismatch (exit code 1).
3. **Provenance label on every output.** The text is
   `Rendered in Blender Cycles from a verified MartyGraphics export (engine <commit>, scene <id>)`.
   - PNG master frames: PNG text metadata `Note` (no burn-in; the frames stay clean).
     The stamp writes no date, host name or file path.
   - MP4 and poster: burned-in caption at the bottom of the image (turn off with `--no-burn-in`
     only for a separate edit that adds the label itself).
   - `PROVENANCE.txt` in the output directory and in `frames/`, and `render-report.json`.
4. **The simulator has priority.** On the render laptop the landing-lab simulator
   (ArduPilot SITL, Gazebo, MAVProxy, the lab runner, `scripts/sitl-up`) comes first.
   `render.py` and `selftest.sh` check for those processes and for a held
   `sitl-up.lock` before they start. When the simulator runs, the render does
   not start (exit code 3) unless you give `--wait-for-simulator SEC`. A
   simulator that starts during a render pauses the render between frames (up to
   one hour, then exit 3; continue later with `--resume`). The guard only reads
   `/proc`: it never signals, locks or changes the simulator. Renders run with
   `nice -n 10` (the script also raises its own niceness to 10) and on the GPU.
   Check by hand with `python3 -m mgrender.simguard` in this directory.

## Setup (user space, no sudo)

```sh
tools/render-blender/setup.sh
```

The script installs the official Blender **5.2.4 LTS** Linux build into
`~/opt/blender-5.2.4`, verifies the SHA-256 against the published checksum file
(at least two official sources must agree), fetches the pinned CC0 HDRI (see
[ASSETS.md](ASSETS.md)) and prints the Cycles device. It writes
`~/opt/blender-5.2.4/INSTALL-RECORD.json` (version, URL, SHA-256, checksum sources).
Override with `BLENDER_VERSION`, `OPT_DIR` or `MG_RENDER_ASSETS`.

Device order: OptiX, then CUDA. CPU only with `--allow-cpu`.

## Render an export

```sh
BLENDER=~/opt/blender-5.2.4/blender
cd tools/render-blender
python3 -m mgrender.manifest /path/to/export/scene.manifest.json      # optional dry check
nice -n 10 "$BLENDER" -b --factory-startup -P render.py -- \
    /path/to/export/scene.manifest.json /path/to/out --preset preview
nice -n 10 "$BLENDER" -b --factory-startup -P render.py -- \
    /path/to/export/scene.manifest.json /path/to/out-hero --preset hero      # add --resolution 4k for UHD
```

Use `--factory-startup` so that no user add-on or preference changes the result.

| Preset | Resolution | Max samples | Adaptive threshold | Look | Master PNG |
| --- | --- | --- | --- | --- | --- |
| `preview` | 1280x720 | 48 | 0.05 | AgX - Base Contrast | 8-bit |
| `hero` | 1920x1080 (`--resolution 4k` for 3840x2160) | 512 | 0.01 | AgX - Medium High Contrast | 16-bit |

Both presets: Cycles path tracing on the GPU, adaptive sampling, denoising
(OptiX denoiser on OptiX, else OpenImageDenoise) with albedo and normal passes,
AgX view transform, motion blur (shutter 0.5, centred on the frame), depth of
field focused on the subject centre, persistent data between frames.

Options:

| Option | Effect |
| --- | --- |
| `--camera auto` | Hero orbit: 40 degrees around the subject over the shot, 22 degrees up. The distance is solved so that the motion bounds of all frames stay inside 86 % of the frame at every orbit angle. |
| `--camera export` / `--camera NAME` | Use the first manifest camera, or the named export camera (with its animation). Default: `export` when the manifest lists a camera, else `auto`. |
| `--backdrop studio` | Default. Curved cyclorama, soft studio HDRI, the HDRI hidden from camera rays. |
| `--backdrop shadow` | Shadow catcher over a plain background. Master frames are RGBA; the MP4 and poster put them over a light grey. |
| `--resolution 720p\|1080p\|1440p\|4k\|WxH`, `--samples N` | Override the preset. |
| `--frames A-B` | Render only frames A..B (the full export is still checked). |
| `--no-motion-blur` | Frame-exact stills. |
| `--resume` | Keep frames that exist in `<out>/frames`. |
| `--wait-for-simulator SEC` | Wait up to SEC seconds for the simulator to stop before the start. |

Exit codes: 0 done, 1 export refused, 2 usage, 3 simulator running,
4 motion check failed, 5 render or encode failure.

### Materials

Look-dev replaces material slots with procedural presets: `polished_metal`,
`brushed_metal` (radial anisotropy), `painted_metal` (clear coat),
`anodised_aluminium`, `rubber`, `carbon_fibre` (coated weave), `glass`
(covers), `plastic`. Choice order: manifest `parts[].material.preset`, then
the name rules on the readable `parts[].label` (for example "Sun gear 1"), then
the same rules on the glTF node name (often a part id such as `sun1`), using the
rules in [mgrender/presets.py](mgrender/presets.py) (for example
`cover|window|canopy` -> glass, `shaft|bearing|bolt` -> polished, `gear|blade|rotor`
-> brushed), then the glTF material values (metallic, roughness, alpha). Painted
and anodised parts keep the exported base colour unless the manifest gives
`baseColor`. Textured imported materials stay unchanged unless the manifest
names a preset. `render-report.json` lists each part's preset and the reason.

## Outputs

```
<out>/frames/frame_0000.png ...   master frames (export frame numbers, provenance metadata)
<out>/frames/PROVENANCE.txt
<out>/<scene>-<preset>.mp4        H.264, yuv420p, fast start (moov before mdat), burned-in label
<out>/<scene>-<preset>-poster.png poster frame (manifest posterFrame, default the middle frame)
<out>/render-report.json          checks, settings, device, time per frame, output SHA-256
<out>/PROVENANCE.txt
```

Blender's MP4 writer puts the `moov` box last; `mgrender/faststart.py` moves it
before `mdat` and fixes the chunk offsets (pure Python, no system FFmpeg).
The encode pass uses the Standard view transform, so AgX is applied once.

## Export manifest (format `martygraphics.render-export/1`)

The MartyGraphics exporter writes this JSON next to the `.glb`:

```json
{
  "format": "martygraphics.render-export/1",
  "engine": {"name": "MartyGraphics", "commit": "<40-hex engine commit>"},
  "scene": {"id": "robot-joint-gearbox", "title": "optional"},
  "glb": {"file": "robot-joint-gearbox.glb", "sha256": "<64 hex>"},
  "fps": 30,
  "frameCount": 240,
  "posterFrame": 120,
  "parts": [{"name": "sun1", "label": "Sun gear 1", "gltfMaterial": "steel",
             "material": {"preset": "brushed_metal", "baseColor": [0.7, 0.7, 0.72]}}],
  "cameras": [{"name": "hero"}]
}
```

Requirements that the check enforces:

- `engine.commit` is hex; `scene.id` is a short identifier; `fps` is an integer 1..240.
- `glb.file` is a relative path inside the export directory; its SHA-256 equals `glb.sha256`.
- The `.glb` holds exactly one animation (or the manifest names it in `animation`,
  and it is the first), with node translation/rotation/scale channels only.
- Every key time is on the frame grid `t = k / fps` (within 0.001 frame), the first key is at `t = 0`,
  and the last key is at `(frameCount - 1) / fps`. Bake one key per frame.
- Node names are unique and at most 63 bytes (Blender's limit); every `parts[].name`
  is a node; every `cameras[].name` is a camera node. Animated nodes use TRS, not `matrix`.
- `parts[].label` and `parts[].gltfMaterial` are strings when present. `parts[].material` is empty
  (`null`, `{}` or `""`: no override) or an object whose `preset` is one of the presets below and
  whose `baseColor` is 3 numbers in 0..1.
- `posterFrame` (optional) is in `0..frameCount-1`.

`parts`, `cameras`, `posterFrame` and `animation` are optional. Unknown keys are ignored.

## What the checks prove

1. **Export check** (`mgrender/manifest.py`, no Blender): SHA-256, fps, frame count,
   frame grid, names (above).
2. **Import check**: Blender's glTF importer maps time `t` to frame `t * fps`
   (frame 0 is `t = 0`). After import, the script evaluates the glTF node
   hierarchy and animation in pure Python at every frame, converts it to Blender
   axes (`(x, y, z) -> (x, -z, y)`) and compares it with every imported object's
   world matrix at every frame. Tolerance: `1e-5 x scene extent + 1e-6` (metres).
   Mesh local bounds must match the glTF `POSITION` min/max.
3. **Look-dev check**: after all look-dev, the world matrices at every frame must be
   bit-identical to step 2, and the SHA-256 of all vertex positions must be unchanged.

Motion blur integrates around each frame time (shutter 0.5 centred on the frame).
Use `--no-motion-blur` when a frame must show one exact instant.

## Self-test (needs no export)

```sh
tools/render-blender/selftest.sh [work-dir]
```

It builds two spur gears (24 and 12 teeth, module 4 mm, 2:1) in Blender, exports
them as `.glb` + manifest (48 frames at 24 fps), checks the 2:1 ratio from the
`.glb` alone, checks that a changed `.glb`, a wrong fps and a wrong frame count
are refused, and then renders the full preview pipeline. The fixture uses the
engine commit `0000000`: it is a pipeline test, not a MartyGraphics-verified mechanism.

Result on the render laptop (2026-11-11, RTX 3060 Laptop GPU 6 GB, OptiX, Blender 5.2.4):
preview 1280x720 48 frames, first frame 1.7 s, then 1.1 s per frame, 57 s in total
with encode; motion check max error 3e-7 m (tolerance 4e-6 m), look-dev drift 0.
A 3-frame hero smoke test (1920x1080, 512 samples): about 30 s per frame.

Unit tests for the Blender-free parts run in CI: `python3 -m unittest discover -s tools/tests`.

## Limits

- Skins, morph targets, `KHR_animation_pointer` and sparse accessors are refused or not checked.
- The auto orbit frames the axis-aligned motion bounds; very long, thin subjects get extra margin.
- The importer applies a fixed axis correction to cameras and lights, so the motion check
  compares their positions only.
