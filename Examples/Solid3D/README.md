# Solid 3D example

A planetary gear set described in
[`Models/planetary.json`](Sources/MartySolid3D/Models/planetary.json)
(sun 24 teeth, three planets of 18, fixed ring of 60, carrier output) and a
Swift-built slider-crank. Both are original synthetic schematic teaching models.

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

The format is documented in [docs/SOLID-3D.md](../../docs/SOLID-3D.md).
