# Solid 3D example

A planetary gear set described in
[`Models/planetary.json`](Sources/MartySolid3D/Models/planetary.json)
(sun 24 teeth, three planets of 18, fixed ring of 60, carrier output) and a
Swift-built slider-crank. Both are original synthetic schematic teaching models.

## How the models work

The sun gear (24 teeth) sits in the middle and is the
input. Three planet gears (18 teeth) mesh with it and with the ring gear (60 teeth) around
them. The ring is held still, so when the sun turns, the planets are pushed around inside
the ring. Their pins sit on the blue carrier, and the carrier is the output. It turns once
for every (24 + 60) ÷ 24 = 3.5 turns of the sun: slower, but with 3.5 times the torque.
The labelled exploded view shows each part, in the order they stack on the shaft.

The slider-crank turns spinning motion into back-and-forth motion, as in an engine or a pump.
The crank (radius 18 mm) turns, and the connecting rod (62 mm) pushes and pulls the piston
along the cylinder. The piston travels twice the crank radius, 36 mm, per turn. The
cylinder is drawn as a section cut, so you can see the piston inside.

From the repository root, with Swift 6 on macOS 14 or later:

```sh
swift run --package-path Examples/Solid3D marty-solid3d --verify
swift run --package-path Examples/Solid3D marty-solid3d --export NEW_DIR   # NEW_DIR must not exist
swift run --package-path Examples/Solid3D marty-solid3d --preview
swift run --package-path Examples/Solid3D marty-solid3d --snapshot hero-snapshot.json
```

`--verify` parses the JSON, checks that the solved carrier ratio equals
Zs / (Zs + Zr) = 24/84, that the gear-ratio residuals are zero, that no tooth
outline enters a mating gear over 240 sun angles, that every mesh is closed, and
that the slider-crank rod always reaches the crank pin.

`--export` renders everything from the bundled JSON (the slider-crank still comes
from `MGSolidModels.sliderCrank()`): `hero.png`, `hero-clean.png`,
`exploded-labelled.png`, one `step-N.png` per authored step, a 12-second
seamless `planetary-loop.mp4` (plus `planetary-loop.gif` and PNG frames), a
6-second `planetary-explode.mp4` (plus PNG frames), `slider-crank-section.png`,
`hero-snapshot.json` and a `manifest.json` with sizes and SHA-256 digests.

The loop is seamless because the sun turns 3.5 times (84 whole tooth pitches)
while the carrier turns exactly once and the camera orbits 360 degrees.

`--preview` opens a window with SceneKit orbit controls, an explode slider and
play/pause. It needs a logged-in desktop session.

## Check or render any model

`marty-solid` works on any solid assembly JSON file, written by a person or by an AI model:

```sh
swift build -c release --package-path Examples/Solid3D
B=$(swift build -c release --package-path Examples/Solid3D --show-bin-path)
$B/marty-solid check my-model.json             # JSON report; exit 0 accepted, 1 refused
$B/marty-solid render my-model.json NEW_DIR    # stills, one per step, loop GIF, snapshot
```

- `check` reads at most 64 KiB (the format limit) and refuses larger or non-regular
  files. It prints a JSON report. A refused model gives the exact reason and part,
  for example `{"ok": false, "reason": "constraint.gearMesh.distance", "part": "planet1"}`,
  so an author or a model can fix it. An accepted model lists its parts, triangles,
  steps, the gear ratios the engine solved, and its checks: closed meshes and a tooth
  sweep with the smallest clearance. If a model parses but fails a check (an open mesh,
  or teeth overlapping by more than 0.01 module), `ok` is false with `check.meshOpen` or
  `check.gearsInterpenetrate`.
- `render` writes `hero.png`, `exploded.png`, one captioned `step-N.png` per authored
  step (with its highlight, explode amount and camera), a 12-second `loop.gif`
  (120 frames at 0.10 s: one orbit, one input turn and an explode beat; `--no-loop`
  skips it), `snapshot.json` for other renderers such as the path tracer, and a
  `manifest.json` with SHA-256 digests and the measured render time. `--size WxH`
  sets the still size (default 1280x800). The output directory must not exist and its
  parent must; a failed render removes the partial directory. A step's `spin` is played
  as that many input turns.

## Components

A model can use reusable components instead of describing every part again, for
example `{"id": "stage", "use": "planetaryStage", "with": {"planets": 3}}`.
[`planetary-components.json`](Sources/MartySolid3D/Models/planetary-components.json)
(12 lines) and
[`slider-crank-component.json`](Sources/MartySolid3D/Models/slider-crank-component.json)
(8 lines) are the two models above built this way.

```sh
$B/marty-solid components                                   # one-line JSON catalog of the built-in components
$B/marty-solid component check my-part.json                 # validate a new component definition
$B/marty-solid component check my-part.json --with teeth=18 # ... and instantiate it with other values
$B/marty-solid check my-model.json --component my-part.json # use a new component before it is built in
```

- `components` prints every component's id, one-line description, parameters
  (default, min, max, integer), inner part ids and anchors. `--component FILE` adds
  more definitions first.
- `component check` validates the definition (closed keys, parameters, expressions,
  references), compiles the component on its own at its defaults, then instantiates it
  with the `--with` values and runs the same mesh and gear checks as `check`. It prints
  the catalog entry, a ready `use` entry, the parts, triangles and solved ratios. A
  refusal gives the reason and part, for example
  `{"ok": false, "reason": "component.param.range.idlerTeeth", "part": "idlerTrain"}`.
- `check` and `render` accept `--component FILE` (repeatable; a later file may use an
  earlier one). A refused component file is reported with `"component": FILE`.

To add a component to the built-in library, open a pull request that adds its JSON
to `MGSolidBuiltInComponents.sources`; the tests compile every built-in.

The format is documented in [docs/SOLID-3D.md](../../docs/SOLID-3D.md).
