# A small native scene gallery

These examples use the public format and drawing primitives. They show different
uses of the engine without implying a curriculum, solver, running infrastructure
service, or AI model.

| Example | What to notice | Source |
| --- | --- | --- |
| Tree search | Follow comparisons through a binary search tree. | [tree.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json) |
| Two pointers | Move through an array to find two numbers totaling 14. | [two-pointers.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json) |
| Message handoff | A step changes the highlighted node in a directed diagram; no queue is executed. | [handoff.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json) |
| Sampled function | Seven supplied points sketch y = x²; the engine does not derive them. | [function.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/function.json) |
| Synthetic counts | Compare Alpha 18, Beta 30, Gamma 24. Every value is invented. | [counts.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json) |
| Geometric motion | A marker takes two seconds from A to B, then returns. No force model is implied. | [motion.json](../Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json) |

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
  This gallery uses the two current built-ins and generic primitives only.

The capture inventory will record source revision, exact commands, dimensions,
frame count/timing, hashes and the producing renderer for each accepted asset.
Do not substitute a mockup when a native capture is unavailable.
