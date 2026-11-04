<div align="center">

# MartyGraphics

### Make the idea visible.

Validated JSON → native diagrams, walkthroughs, and animation in SwiftUI.

[Examples](docs/SHOWCASE.md) · [Quick start](#quick-start) · [Tutorial](docs/GETTING-STARTED.md) · [Contribute](CONTRIBUTING.md)

</div>

<p align="center">
  <a href="docs/SHOWCASE.md"><img src="docs/assets/native/two-pointers.gif" width="840" alt="Native two-pointer walkthrough: pointers move through 2, 5, 9, 14 and find 5 + 9 = 14 in four steps."></a>
</p>

**An array walkthrough, rendered by the public Swift engine.** Four native frames,
1.2 seconds each (4.8-second loop; 53 KiB).
[Still alternative](docs/assets/native/two-pointers.png) ·
[Scene source](Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json) ·
[Run it](Examples/Showcase/README.md) · [Capture receipt](docs/assets/native/provenance.json)

Follow a tree search, move pointers through an array, trace a message between nodes,
or plot the samples you supply. MartyGraphics handles validation, layout, rendering,
steps, and motion. Your application supplies the content and decides what happens next.

## Small scenes, different ideas

| Explore | What the public package does | Source |
| --- | --- | --- |
| **Algorithms** | Follow a binary search tree or move two pointers toward a matching pair. | [Tree](Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json) · [Array](Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json) |
| **Systems** | Draw nodes, directed edges, and step-controlled highlights for an illustrative message handoff. | [Handoff](Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json) |
| **Math** | Draw a function from supplied points, with labeled axes. The engine plots the data; it does not solve equations. | [Sampled function](Examples/Showcase/Sources/MartyShowcase/Scenes/function.json) |
| **Data** | Compare explicit quantities with labeled bars. These counts are invented. | [Synthetic counts](Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json) |
| **Motion** | Animate a geometric marker using the engine timeline. | [Moving marker](Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json) |

[Open the showcase and its capture recipe →](docs/SHOWCASE.md)

### A few different ways to explain

**Trace a handoff.** Nodes, directed edges and step-controlled highlights illustrate
Source → Queue → Worker; the diagram does not execute a queue.

[![Native directed diagram connecting Source, Queue and Worker, with Worker highlighted.](docs/assets/native/handoff.png)](docs/assets/native/handoff.png)

[Scene source](Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json) · [Run](Examples/Showcase/README.md)

**Plot the points you supply.** Seven samples sketch y = x². The engine draws them;
it does not solve the function.

[![Native plot connecting seven supplied samples of y equals x squared from x minus three to three.](docs/assets/native/function.png)](docs/assets/native/function.png)

[Scene source](Examples/Showcase/Sources/MartyShowcase/Scenes/function.json) · [Run](Examples/Showcase/README.md)

**Compare quantities.** Alpha 18, Beta 30 and Gamma 24 are invented counts.

[![Native bar chart: Alpha 18, Beta 30 and Gamma 24, with values and category labels.](docs/assets/native/counts.png)](docs/assets/native/counts.png)

[Scene source](Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json) · [Run](Examples/Showcase/README.md)

<details>
<summary>More native examples: tree search and timeline animation</summary>

**Follow a search.** Find 8 through the path 12 → 5 → 8.

[![Native binary search tree with the search path to eight highlighted.](docs/assets/native/tree.png)](docs/assets/native/tree.png)

[Scene source](Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json) · [Run](Examples/Showcase/README.md)

**Move through a scene.** A geometric marker travels between A and B on the engine
timeline. This is animation, with no force simulation.

![Native timeline animation moving a marker back and forth between A and B.](docs/assets/native/motion.gif)

32 frames; stored GIF delay 0.13 seconds per frame, **4.16 seconds per loop**
(about 7.69 fps; 124 KiB).
[Still alternative](docs/assets/native/motion.png) ·
[Scene source](Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json) · [Run](Examples/Showcase/README.md)

</details>

[Six-scene overview](docs/assets/native/overview.png) · [Full static gallery](docs/SHOWCASE.md#static-gallery)

These are **native SwiftUI ImageRenderer exports** of `MGCanvasRenderer` /
`MGTimeline`, with a small SwiftUI caption wrapper. They are not full-app
screenshots or browser recreations. All are original synthetic examples under
[Apache-2.0](LICENSE). Individual views provide larger labels than the overview;
open any still at full size. GitHub controls GIF playback; static alternatives
are available for every animated example.

## Why use it?

- **Validate before drawing.** Closed keys, bounds, references, text limits, and
  highlight-cycle checks reject invalid scenes. Failed patches preserve the old scene.
- **Explain one step at a time.** Reveal items, move pointers, focus a node, and
  apply validated edits without replacing the whole explanation.
- **Keep the host in control.** Use `MartyGraphicsView` for a native board or
  `MGCanvasRenderer` / `MGTimeline` for deterministic frame generation.
- **Extend the format.** Register templates through the validated pack API.
  The built-in templates are `bst` and `two_pointers`.

## Quick start

Use **Swift 6 on macOS 14+**. The library can also be embedded in an iOS 17+ app.
There are no external Swift package dependencies, credentials, or network services
needed to build the engine or run these examples.

```sh
git clone https://github.com/morrowdock/martygraphics.git
cd martygraphics
swift build && swift test
swift run --package-path Examples/Showcase marty-showcase --verify
```

`--verify` validates six bundled synthetic scenes and the core pack. Build, 23
tests, verification and native export passed at the [capture source revision](docs/assets/native/provenance.json).
To open the interactive gallery, run
`swift run --package-path Examples/Showcase marty-showcase --preview`.
Interactive control/accessibility testing remains pending; the capture receipt
covers offscreen export. See [the runnable example](Examples/Showcase/README.md)
for the export command and platform details.

For an existing app, add the `MartyGraphics` Swift package product, then parse a scene:

```swift
import Foundation
import MartyGraphics

let json = #"{"v":1,"template":"bst","params":{"values":[12,5,19,2,8],"find":8}}"#
let scene = try MGParser.scene(data: Data(json.utf8)).get()
// In your SwiftUI view body:
MartyGraphicsView(scene: scene)
```

The [tutorial](docs/GETTING-STARTED.md) connects scenes, safe patches, streams, and
the host view. The [protocol reference](docs/PROTOCOL.md) lists the exact limits.

## Scope and status

**Early preview.** APIs and the wire format may change. This is the scene engine,
not a complete learning app or a collection of courses.

| In this public package | Boundary |
| --- | --- |
| SwiftUI Canvas and a SceneKit renderer for supported 3D primitives | Current renderers require Apple frameworks; Windows/Linux builds and native Swift browser execution are unsupported. This is a current implementation choice, not a requirement imposed by iPad. |
| Parser, grammar, patches, streams, layout, timeline, steps, template/pack API | The host supplies JSON and interaction. No model, hosted generation API, screen overlay agent, equation solver, or arbitrary code executor is bundled. |
| BST and two-pointer built-ins; generic primitives for custom scenes | No course catalog, premium pack, private app adapter, or removed mechanics walkthrough is included. |
| Six synthetic 2D examples and a local native showcase | A flow diagram does not run a queue; sample plots/counts are supplied data. The gallery is not evidence of a complete app or measured 3D performance. |

See the [public versus app matrix](docs/CAPABILITIES.md),
[quality and measurement plan](docs/QUALITY.md), and
[portable-core proposal](docs/PORTABILITY-PROPOSAL.md).
Use [local maintainer validation](docs/LOCAL-VALIDATION.md) for hygiene and DCO;
hosted Ubuntu checks are manual opt-in. The [Mac verification steps](docs/VERIFY-ON-MAC.md)
cover Apple-framework builds. Each candidate needs reviewed evidence and its own
authenticated maintainer status.

## Read, build, contribute

- [Showcase and original example sources](docs/SHOWCASE.md)
- [Tutorial](docs/GETTING-STARTED.md) · [Protocol](docs/PROTOCOL.md) · [Structural grammar](Sources/MartyGraphics/MGGrammar.swift)
- [Template API](Sources/MartyGraphics/MGTemplates.swift) · [Pack API](Sources/MartyGraphics/MGPack.swift)
- [Source provenance](docs/EXPORT.json) · [Third-party inventory](docs/THIRD-PARTY.md)
- [Public sync ownership and review process](docs/PUBLIC-SYNC.md)
- [Apache-2.0 license](LICENSE) · [Notice](NOTICE)
- [Contributing and DCO](CONTRIBUTING.md) · [Code of conduct](CODE_OF_CONDUCT.md) · [Security](SECURITY.md)

[Morrowdock](https://morrowdock.app) is the host application's website. Its browser
demonstrations are separate implementations, not this Swift package running in a browser.
