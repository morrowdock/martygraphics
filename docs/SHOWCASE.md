# A small native scene gallery

These examples use the public format and drawing primitives. They show different
uses of the engine without implying a curriculum, solver, running infrastructure
service, or AI model.

| Example | In `--preview` | What to notice | Source |
| --- | --- | --- | --- |
| Tree search | Follow a search | Follow comparisons through a binary search tree. | [tree.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json) |
| Two pointers | Walk an array | Move through an array to find two numbers totaling 14. | [two-pointers.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json) |
| Message handoff | Trace a handoff | A step changes the highlighted node in a directed diagram; no queue is executed. | [handoff.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json) |
| Sampled function | See the samples | Seven supplied points sketch y = x²; the engine does not derive them. | [function.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/function.json) |
| Synthetic counts | Compare quantities | Compare Alpha 18, Beta 30, Gamma 24. Every value is invented. | [counts.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json) |
| Geometric motion | Move through a scene | A marker takes two seconds from A to B, then returns. No force model is implied. | [motion.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json) |
| Shortest path | Find the cheapest route | Dijkstra settles six routers one at a time; the cheapest route 0→2→1→3→4→5 costs 13. Opt-in graph pack. | [shortest-path.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/shortest-path.json) |

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
