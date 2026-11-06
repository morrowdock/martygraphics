# Path-traced gearbox

`marty-pathtrace` renders a procedurally generated two-stage gearbox with
`MartyGraphicsPathTracer`, the package's Metal GPU path tracer. Every pixel comes
from this code: there are no images, models or stock assets.

- A 15-tooth pinion drives a 30-tooth spur gear (2:1).
- A planetary stage follows: 24-tooth sun, three 18-tooth planets and a fixed 60-tooth
  ring (3.5:1). The overall ratio is 7:1.
- Teeth have true involute flanks and filleted roots. The meshing phase of every gear is
  computed, and `--verify` checks it.

This is a schematic teaching model, not a validated mechanical design.

## How the gearbox works

The input shaft turns the small 15-tooth pinion. It drives a 30-tooth gear,
which turns half as fast (30 ÷ 15 = 2:1). That gear spins the 24-tooth sun gear in the middle
of a planetary set. Three 18-tooth planet gears mesh with the sun and with the 60-tooth ring
around them. The ring is fixed, so the planets roll around inside it and carry their
carrier along, slowly. The carrier turns once for every 1 + 60 ÷ 24 = 3.5 turns of the sun.
Together: 2 × 3.5 = 7 turns of the input for one turn of the output. Planetary sets are
used where a big reduction must fit in a small space, such as in car automatic
transmissions, power drills and helicopter rotor gearboxes.

## Run

From the repository root, on a Mac with Apple silicon (Metal ray tracing):

```sh
swift build -c release --package-path Examples/PathTrace
Examples/PathTrace/.build/release/marty-pathtrace --verify
Examples/PathTrace/.build/release/marty-pathtrace --still /tmp/gearbox-stills --size 1920x1080 --spp 256
Examples/PathTrace/.build/release/marty-pathtrace --loop /tmp/gearbox-loop --size 1280x720 --spp 48
Examples/PathTrace/.build/release/marty-pathtrace --sidebyside /tmp/gearbox-sbs
```

Each command writes to a **new** directory, with a JSON file that records settings,
samples per pixel, GPU time and SHA-256 digests. `--frames DIR --times 0,5,8.3` renders
single moments of the animation. `--sidebyside` needs a width above 844 pixels, because
the code panel is 780 pixels wide.

On an M1 Mac mini, a 1920x1080 still at 768 samples per pixel took about 2.5 minutes. The
10-second 1280x720 loop took about 33 minutes (112 samples per pixel per frame). The published
GIF is a 480x270 downscale; GIF delays are stored in hundredths of a second, so its 120 frames
play for 9.6 seconds.

## What the renderer does

- Path tracing with next-event estimation and multiple importance sampling, Russian roulette
  and path regularisation.
- Materials: anisotropic GGX metals (brushed steel, brass), plastic, clear coat, rough and
  smooth glass, diffuse and emissive.
- A procedural, importance-sampled studio environment and area lights. Four of the five studio
  lights are hidden from the camera but still appear in reflections.
- Thin-lens depth of field, an edge-aware à-trous denoiser, and an ACES filmic tonemap.
- Deterministic renders for a given seed on the same GPU and toolchain.

Limits: no motion blur; the denoiser works on one frame at a time; glass blocks shadow rays.

The published captures and their receipt are in
[`docs/assets/pathtrace`](../../docs/assets/pathtrace/provenance.json).
