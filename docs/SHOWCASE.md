# A small native scene gallery

These examples use the public format and drawing primitives. They show different
uses of the engine without implying a curriculum or a running service.

> **About the 3D loops on this page.** GitHub shows them as GIF images, not video. A GIF
> has at most 256 colours, and these previews are 480 to 640 pixels wide at 10 to 12 frames per
> second, so they look rougher and less smooth than the real output. The turbofan and gearbox source videos are
> 1280 pixels wide at 30 and 24 frames per second: <a href="https://morrowdock.app/mg/turbofan/turbofan-loop.mp4">turbofan (MP4)</a> ·
> <a href="https://morrowdock.app/mg/pathtrace/gearbox-loop.mp4">path-traced gearbox (MP4)</a>. Run an example to see the engine live.

## From a prompt

The first example on this page was written by an AI model from one question. The others are
hand-built (each says so).

[![AI-written two-stage planetary gearbox, exploded: brass suns, steel planets, blue and orange carriers, two ring gears.](assets/from-a-prompt/robot-joint/exploded.png)](assets/from-a-prompt/robot-joint/loop.gif)

| | |
| --- | --- |
| Prompt | "Show a two-stage planetary gearbox like in a robot joint." |
| Model | Claude Haiku 5.5, fresh process, no tools, only the public docs at commit `17396a2f` |
| Attempt 1 | Refused: `constraint.gearMesh.phase` on `ring1` (sun 20, ring 56: 76 ÷ 3 is not whole) |
| Attempt 2 | Accepted: sun 24, planets 18, ring 60; 19 parts, 12 meshes, output 4/49 (12.25:1) |
| Time | 121 s for both attempts |
| Grader | Independent model, against pre-registered checks: mechanics, explanation and labels pass |

[Loop](assets/from-a-prompt/robot-joint/loop.gif) · [JSON](assets/from-a-prompt/robot-joint/robot-joint-gearbox.json) ·
[Refused first try](assets/from-a-prompt/robot-joint/attempt-1-refused.json) · [Run receipt](assets/from-a-prompt/robot-joint/provenance.json)

**What the full test found.** Haiku answered 50 pre-registered questions. All 40 buildable ones
were accepted within three repairs (median 25 s), but only 29 of 40 were fully correct in
mechanics, and 4 of 50 explanations had a critical error. The main failures: the model quietly
swapped bevel, worm or crown gears for flat spur gears; its text sometimes gave a number the solved
model did not have; and it skipped features the docs did not show by example. We change the engine
only from failures like these.

## Turbofan cutaway

A schematic two-spool, high-bypass turbofan built and rendered by the solid engine from
[38 lines of JSON](../Examples/Turbofan/Sources/TurbofanKit/Models/turbofan.json): a 20-blade
fan, 3 LP and 6 HP compressor stages, an annular combustor, 2 HP and 4 LP turbine stages, and
an LP shaft (blue) inside the HP shaft (orange). The model is JSON written for this example in
the documented format, not the output of a prompt run. It is a teaching model, not a real
engine design.

[![Turbofan cutaway turning: fan, compressors, combustor and turbines exposed inside a half-cut nacelle.](assets/turbofan/turbofan-loop.gif)](assets/turbofan/pathtraced-hero.png)

[Path-traced still](assets/turbofan/pathtraced-hero.png) · [Labelled cutaway](assets/turbofan/labelled.png) ·
[Exploded](assets/turbofan/exploded.png) · [Loop (GIF, 640×400, 10 fps, 12 s)](assets/turbofan/turbofan-loop.gif) ·
[Video (MP4, 1280×800, 30 fps)](https://morrowdock.app/mg/turbofan/turbofan-loop.mp4) ·
[Run it](../Examples/Turbofan/README.md) · [Render receipt](assets/turbofan/provenance.json)

**How a turbofan works.** The big fan at the front pulls in a huge flow of air (suck). A small
part of it goes into the core, where rows of spinning blades and fixed vanes squeeze it to many
times its intake pressure (squeeze). Fuel burns steadily in the ring-shaped combustor, so the air
gets very hot and expands (bang). The hot gas rushes through the turbines and spins them (blow):
the HP turbine drives the HP compressor, and the LP turbine drives the fan through a shaft that
runs inside the HP shaft. Here the HP shaft turns three times as fast as the LP shaft. Most of the
fan's air goes around the core through the bypass duct, and in a high-bypass engine like this it
gives most of the thrust.

## Native scenes

| Example | In `--preview` | What to notice | Source |
| --- | --- | --- | --- |
| Tree search | Follow a search | Follow comparisons through a binary search tree. | [tree.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json) |
| Two pointers | Walk an array | Move through an array to find two numbers totaling 14. | [two-pointers.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json) |
| Message handoff | Trace a handoff | A step changes the highlighted node in a directed diagram; no queue is executed. | [handoff.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json) |
| Sampled function | See the samples | Seven supplied points sketch y = x²; the engine does not derive them. | [function.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/function.json) |
| Synthetic counts | Compare quantities | Compare Alpha 18, Beta 30, Gamma 24. Every value is invented. | [counts.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json) |
| Geometric motion | Move through a scene | A marker takes two seconds from A to B, then returns. No force model is implied. | [motion.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json) |
| Shortest path | Find the cheapest route | Dijkstra settles six routers one at a time; the cheapest route 0→2→1→3→4→5 costs 13. Opt-in graph pack. | [shortest-path.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/shortest-path.json) |

## Solid 3D from JSON

A planetary gear set built and rendered in real time by the solid engine from
[53 lines of JSON](../Examples/Solid3D/Sources/MartySolid3D/Models/planetary.json).

[![Solid 3D planetary gear set exploded along its shaft with part labels.](assets/solid/exploded-labelled.png)](assets/solid/exploded-labelled.png)

[Assembled](assets/solid/hero.png) · [Slider-crank cutaway](assets/solid/slider-crank-section.png) ·
[Loop (GIF, 480×300, 10 fps, 12 s)](assets/solid/planetary-loop.gif) · [Run it](../Examples/Solid3D/README.md) ·
[Render receipt](assets/solid/provenance.json)

**How a planetary gear set works.** The sun gear (24 teeth) sits in the middle and is the
input. Three planet gears (18 teeth) mesh with it and with the ring gear (60 teeth) around
them. The ring is held still, so when the sun turns, the planets are pushed around inside
the ring. Their pins sit on the blue carrier, and the carrier is the output. It turns once
for every (24 + 60) ÷ 24 = 3.5 turns of the sun: slower, but with 3.5 times the torque.
The labelled exploded view shows each part, in the order they stack on the shaft.

## Path-traced gearbox

A procedurally generated two-stage gearbox, path traced on an
Apple M1 GPU by `MartyGraphicsPathTracer`: 1920×1080, 768 samples per pixel, about
2.5 minutes per still. No images, models or stock assets.

[![Path-traced steel and brass gearbox with involute teeth on a dark studio floor.](assets/pathtrace/hero.png)](assets/pathtrace/hero.png)

[Exploded view](assets/pathtrace/exploded.png) · [Code beside the render](assets/pathtrace/side-by-side.png) ·
[Loop (GIF, 480×270, 12.5 fps, 9.6 s)](assets/pathtrace/gearbox-loop.gif) ·
[Video (MP4, 1280×720, 24 fps)](https://morrowdock.app/mg/pathtrace/gearbox-loop.mp4) ·
[Run it](../Examples/PathTrace/README.md) · [Render receipt](assets/pathtrace/provenance.json)

**How it works.** The input shaft turns the small 15-tooth pinion. It drives a 30-tooth gear,
which turns half as fast (30 ÷ 15 = 2:1). That gear spins the 24-tooth sun gear in the middle
of a planetary set. Three 18-tooth planet gears mesh with the sun and with the 60-tooth ring
around them. The ring is fixed, so the planets roll around inside it and turn the carrier that holds
them, slowly. The carrier turns once for every 1 + 60 ÷ 24 = 3.5 turns of the sun.
Together: 2 × 3.5 = 7 turns of the input for one turn of the output. Planetary sets are
used where a big reduction must fit in a small space, such as in car automatic
transmissions, power drills and helicopter rotor gearboxes.

## Run or reproduce

Follow the [native showcase instructions](../Examples/Showcase/README.md).
The [exporter source](../Examples/Showcase/Sources/MartyShowcase/Showcase.swift)
uses `MGTimeline.items`, `MGTimeline.frame`, `MGViewport`, and `MGCanvasRenderer`,
then renders the native frames with SwiftUI `ImageRenderer`.

All examples are original synthetic material under [Apache-2.0](../LICENSE).
No private course fixture, premium pack, browser screenshot, concept, or external
artwork belongs to this set.

## Native versus browser demonstrations

- Native exports are engine frames with a small SwiftUI card/caption wrapper,
  not screenshots of the full Morrowdock application.
- [Morrowdock's website](https://morrowdock.app) can demonstrate related ideas
  using browser code. A browser recreation is separate from Swift execution.
- A concept or private/unmerged pack is not evidence of a public capability.
  This gallery uses the two current built-ins, the public opt-in graph pack and
  generic primitives only.

## Accepted capture inventory

The [machine-readable receipt](assets/native/provenance.json) pins the capture commit
`9b4ba89780af54d7de7f7e4fd209625a2db24f33` and the SHA-256 of every scene, tool and engine source
file, so it stays checkable after a squash merge. It also records commands, platform,
dimensions, stored timing and artifact digests. Build, 95 tests (zero failures), scene
verification and native export passed on macOS 27.2 / Apple Swift 6.4.2, arm64, SwiftPM debug,
renderer scale 1. Later documentation/CI changes do not change the captured Swift source.

| Asset | Pixels | Size | Timing |
| --- | --- | --- | --- |
| [Overview](assets/native/overview.png) | 1172 × 2116 | 570 KiB | Still; individual views have clearer small labels |
| [Tree](assets/native/tree.png), [array](assets/native/two-pointers.png), [handoff](assets/native/handoff.png), [function](assets/native/function.png), [counts](assets/native/counts.png), [motion](assets/native/motion.png), [shortest path](assets/native/shortest-path.png) | 840 × 662 each | 90–159 KiB each | Stills; motion sampled at one second |
| [Two pointers](assets/native/two-pointers.gif) | 840 × 662 | 53 KiB | 4 frames × 1.2 s = 4.8 s |
| [Shortest path](assets/native/shortest-path.gif) | 840 × 662 | 125 KiB | 8 frames × 1.2 s = 9.6 s |
| [Motion](assets/native/motion.gif) | 840 × 662 | 124 KiB | 32 frames × stored 0.13 s = 4.16 s (about 7.69 fps) |

All eleven images total **1,807,710 bytes (about 1.72 MiB)**. The README shows two small animations
and puts the third in a disclosure. Stills are single-column and can
be opened at full resolution. GitHub controls GIF playback; choose the static
gallery below to avoid the animations. Descriptions and values remain available
as text rather than relying on small image labels alone.

These are offscreen native captures with a caption wrapper. No full-app screenshot,
video, live interactive playback, accessibility, performance or adopter receipt is
claimed. See the [remaining quality work](QUALITY.md).

## Static gallery

Each source link above is runnable in the [same local showcase](../Examples/Showcase/README.md):
pick a scene by its preview title from the table above in `--preview`, or export
the complete set with `--export`.
The accepted receipt covers export; interactive controls still need validation.

### Tree search

Search 12 → 5 → 8, finding 8 in three comparisons.
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json) · [Run](../Examples/Showcase/README.md)

[![Native binary search tree: path twelve, five, eight highlighted.](assets/native/tree.png)](assets/native/tree.png)

### Two pointers

The final step selects 5 + 9 = 14 from [2, 5, 9, 14].
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json) · [Run](../Examples/Showcase/README.md)

[![Native array with five and nine selected for target fourteen.](assets/native/two-pointers.png)](assets/native/two-pointers.png)

### Message handoff

Source → Queue → Worker; the final step highlights Worker. This is a diagram.
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json) · [Run](../Examples/Showcase/README.md)

[![Native directed handoff diagram with Worker highlighted.](assets/native/handoff.png)](assets/native/handoff.png)

### Sampled function

Seven supplied points sketch y = x² from x = −3 to 3, without a solver.
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/function.json) · [Run](../Examples/Showcase/README.md)

[![Native plot of seven supplied samples of x squared.](assets/native/function.png)](assets/native/function.png)

### Synthetic counts

Alpha 18, Beta 30, Gamma 24. Every quantity is invented.
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json) · [Run](../Examples/Showcase/README.md)

[![Native labeled bars comparing eighteen, thirty and twenty-four.](assets/native/counts.png)](assets/native/counts.png)

### Geometric motion

A still sampled at one second between A and B. The timeline animates position;
it does not simulate forces.
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json) · [Run](../Examples/Showcase/README.md)

[![Native geometric marker midway between A and B.](assets/native/motion.png)](assets/native/motion.png)

### Shortest path

Dijkstra over six routers with link latencies in milliseconds. The final step
highlights 0→2→1→3→4→5 at cost 13, the only route at that cost.
[Source](../Examples/Showcase/Sources/MartyShowcase/Scenes/shortest-path.json) · [Run](../Examples/Showcase/README.md)

[![Native weighted graph with the route zero, two, one, three, four, five highlighted and a distance table below.](assets/native/shortest-path.png)](assets/native/shortest-path.png)

[Seven-scene overview](assets/native/overview.png) · [Asset license](../LICENSE) · [Exact provenance](assets/native/provenance.json)
