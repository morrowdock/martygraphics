# Turbofan cutaway example

A two-spool, high-bypass turbofan described in
[`Models/turbofan.json`](Sources/TurbofanKit/Models/turbofan.json) and rendered
two ways: in real time by the solid engine's SceneKit studio renderer, and path traced by
`MartyGraphicsPathTracer` through a small adapter. Every pixel comes from this code and
that JSON. There are no images, models or stock assets.

This is a **schematic teaching model**. It is not a real or validated engine design and is
not based on any manufacturer's engine. Blade counts, stage counts and sizes are plausible
for teaching, not engineering values.

## How a turbofan works

A turbofan is a jet engine with a big fan at the front. A small gas turbine in the middle,
the **core**, turns the fan. Engineers sum up the core in four words: suck, squeeze, bang,
blow.

1. **Suck.** The spinning fan pulls in a huge flow of air. Only the inner part of that air
   goes into the core. The rest goes around it.
2. **Squeeze.** Inside the core, rows of spinning blades (rotors) and fixed vanes (stators)
   push the air into a smaller and smaller space. Each rotor row adds energy and speeds the
   air up; each vane row slows it down again and turns that speed into pressure. In modern
   airliner engines the
   air leaves the compressor at roughly 30 to 50 times the pressure it came in with.
3. **Bang.** Fuel sprays into the ring-shaped (annular) combustor and burns. It burns
   steadily, like a gas burner, not in separate explosions. The air gets very hot and
   expands.
4. **Blow.** The hot gas rushes through the turbines and spins them. Fixed nozzle vanes
   aim the gas onto each row of turbine blades. The turbines take energy from the gas to
   drive the compressors and the fan. What is left leaves the core nozzle as a fast jet.

**Two shafts, one inside the other.** The high-pressure (HP) turbine drives the HP
compressor through the HP shaft. The low-pressure (LP) turbine drives the fan and the LP
compressor through the LP shaft, which runs inside the HP shaft. The two "spools" turn at
different speeds. A fan blade tip is far from the axis, so it moves very fast even at a
modest number of turns per minute; the fan must turn slowly enough that its tips do not go
much faster than sound. The small HP spool can turn much faster. Pilots call the speeds N1 (LP) and
N2 (HP). In this model N2 is exactly 3 × N1.

**Bypass air makes most of the thrust.** Most of the fan's air never enters the core. It
flows down the bypass duct, past the guide vanes that straighten it, and out the back. In
a high-bypass engine like this one, several times more air goes around the core than
through it (about 5 to 12 times in modern airliner engines), and that bypass air gives most
of the thrust. Pushing a lot of air a little faster uses less fuel than pushing a little
air very fast. That is why airliner engines have such big fans.

**Hot parts.** The turbine blades sit in gas hotter than the metal could survive on its
own. Real engines use nickel alloys, ceramic coatings and cooling air to protect them. The
model shows the alloy and coating as materials only; it has no cooling passages.

## What is in the model

| Module | In this model |
| --- | --- |
| Fan | 20 twisted, cambered blades, tip radius 895 mm, LP spool |
| LP compressor | 3 stages: 40 blades per rotor row, 44 vanes per stator row |
| HP compressor | 6 stages: 36 blades per rotor row, 44 vanes per stator row |
| Combustor | Annular liner with 20 fuel nozzles |
| HP turbine | 2 stages: 32 nozzle vanes and 44 blades per stage |
| LP turbine | 4 stages: 40 vanes and 48 blades per stage |
| Shafts | LP shaft (blue) inside the HP shaft (orange); N2 = 3 × N1 |
| Static structure | Nacelle, bypass guide vanes, core cowl, core casing and nozzle, intermediate and rear frames, exhaust cone |

The shafts are colour coded (anodised blue and orange) for teaching; real shafts are bare
steel. Real HP compressors often have more stages (9 or 10 is common) and real rows have
more blades.

## How it was made

* **One JSON file, 38 lines, 23 parts.** The parts use the documented
  [solid assembly format](../../docs/SOLID-3D.md). Casings, the combustor liner and the
  nacelle are `revolvedProfile` walls with a `sweep` of less than a full turn, so the
  cutaway faces are real capped solids, not a clipping trick. Each blade or vane row is one
  `bladeRow`: an airfoil with stagger, twist and camber, wrapped on cylinders and repeated
  around the axis. Rotor and stator rows lean opposite ways, and turbine and compressor
  blades curve opposite ways, as in real machines.
* **Kinematics.** The LP shaft has `"drive": {"input": 1}` and the HP shaft
  `"drive": {"input": 3}`. The fan, compressors and turbines are children of their shaft.
  Everything else is fixed.
* **Teaching steps.** Eight `steps` in the JSON hold the captions, the highlighted parts,
  the parts to frame and the camera. `explode` vectors lift the casings away and leave the
  spinning parts on their shafts below the fixed vanes.
* **Checks.** `--verify` parses the JSON and checks that:
  * every part mesh is closed;
  * the fan, LP compressor and LP turbine turn with the LP shaft, and the HP parts with the
    HP shaft;
  * N2 / N1 measured from the posed parts equals the authored 3 / 1;
  * both spools turn about one engine axis;
  * at 24 sampled angles no rotating vertex changes its radius or axial position.

  Because the rotors are coaxial, a rotating part sweeps exactly the solid of revolution of
  its (radius, axial) "shadow". So two parts that turn at different speeds can only touch if
  their shadows overlap. The check draws every part's shadow on a 1 mm grid and reports each
  rotor's smallest gap to anything that does not turn with it. In this model every gap is at
  least 4 mm.
* **Path tracing.** [`MartySolidRT`](Sources/MartySolidRT/MGSolidRT.swift) turns an
  `MGSolidSnapshot` (plain world-space arrays) into an `MGRTScene`, one mesh per part. It
  maps colours from sRGB to linear, metallic presets to GGX metals and the rest to plastic
  or glass, and it carries the clear coat over. It sits in this example, so the core library
  and the path tracer do not depend on each other. The hero still adds its own studio
  lights and a dark floor.

Measured on an M1 Mac mini: the real-time renderer takes about 0.04 s per 1280×800 frame
(2× supersampled). The 12-second loop (360 frames) exports in under 20 seconds. The
1920×1080 path-traced still takes about 4.3 minutes at 768 samples per pixel. The checked-in
renders and their receipt are in [`docs/assets/turbofan`](../../docs/assets/turbofan/provenance.json). The model
has about 433,000 triangles.

## Run

From the repository root, with Swift 6 on macOS 14 or later:

```sh
swift build -c release --package-path Examples/Turbofan
Examples/Turbofan/.build/release/marty-turbofan --verify
Examples/Turbofan/.build/release/marty-turbofan --export NEW_DIR        # stills, steps, loop MP4 + GIF
Examples/Turbofan/.build/release/marty-turbofan --pathtrace NEW_DIR --size 1920x1080 --spp 768
Examples/Turbofan/.build/release/marty-turbofan --ptloop NEW_DIR --size 960x540 --spp 48   # path-traced 10 s loop
Examples/Turbofan/.build/release/marty-turbofan --view FILE.png --yaw -30 --pitch 20 [--explode 1]
swift test --package-path Examples/Turbofan
```

Each export command writes to a **new** directory. `--export` writes `hero.png`,
`hero-clean.png`, `labelled.png`, `step-1.png` … `step-8.png`, `turbofan-loop.mp4`
(1280×800, 30 fps, 12 s), `turbofan-loop.gif` (640×400, 120 frames at 10 hundredths of a
second, 12.00 s), `loop-poster.png`, `hero-snapshot.json` and `manifest.json` with sizes and
SHA-256 digests. The loop is seamless: the LP spool turns once and the HP spool three times,
so every blade row ends where it started. `--pathtrace` writes `pathtraced-hero.png`,
`pathtraced-hero-clean.png` and `pathtrace.json`. `--ptloop` renders the same seamless
motion with the path tracer (24 fps, 10 s): the rotors move by instance transform, so the
scene is built once. Both need a Metal ray-tracing GPU (any Apple silicon Mac).

## Limits

* Air is not simulated. Nothing here computes flow, pressure, temperature or thrust; the
  numbers in "How a turbofan works" describe real engines in general, not this model.
* The clearance check uses a 1 mm grid, so gaps are estimates to about 1.5 mm, and it covers
  only parts that turn relative to each other. Fixed parts may touch each other (vanes are
  set into the casing walls on purpose).
* Blade rows have straight radial stacking lines and flat tip caps; real blades are swept,
  leaned and have shaped tips and platforms.
* In the highlight steps the solid renderer dims the other parts strongly, so those frames
  are dark around the highlighted parts.
