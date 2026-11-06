# Native showcase

Six original synthetic scene descriptions exercise the public engine:
tree search, two-pointer traversal, message-flow diagrams, sampled functions,
bar comparisons, and geometric motion. No private app, course content, model,
API key, third-party package, or browser renderer is used.

From the repository root, with Swift 6 / macOS 14+:

```sh
swift run --package-path Examples/Showcase marty-showcase --verify
swift run --package-path Examples/Showcase marty-showcase --preview
```

The preview opens a native window. Choose a scene, then use the engine's step/play
controls. The host respects the engine's Reduce Motion handling; static exports
do not establish screen-reader or physical-device accessibility.

## Make a first change

Edit one of the six files in
[`Sources/MartyShowcase/Scenes`](Sources/MartyShowcase/Scenes) in place, then run
`--verify` and `--preview` again. For example, in `counts.json` change Gamma's
`"value"` from 24 to 36. The engine redraws the bar from the new value, but
it does not rewrite authored text. The step's `say` still says Beta is largest,
so update that sentence as well. Values, labels and narration are all authored data.

To see validation work, add a seventh bar or misspell a key such as `"colour"`.
`--verify` should then stop with a reason like `bars.bars` or
`bars.bar.unknown.colour` instead of drawing a partial board. The reason names
the rule, not the file, so undo your last edit to find it.

The showcase loads exactly the six scene IDs listed in
[`Showcase.swift`](Sources/MartyShowcase/Showcase.swift) and checks that six
loaded. A new JSON file in `Scenes` is not picked up automatically. Try a new
scene in your own host instead; the [tutorial](../../docs/GETTING-STARTED.md)
shows a small one.

To export images without opening the preview window:

```sh
swift run --package-path Examples/Showcase marty-showcase --export /tmp/marty-showcase-captures
```

Choose a **new** output directory; export refuses to overwrite an existing directory.
The exporter uses this repository's local `MartyGraphics` package dependency.

Expected output:

- `overview.png`: six native engine boards in a labeled SwiftUI capture layout.
- `tree.png`, `two-pointers.png`, `handoff.png`, `function.png`, `counts.png`, `motion.png`:
  each scene's final step; motion sampled at one second.
- `two-pointers.gif`: each actual engine walkthrough step held for 1.2 seconds.
- `motion.gif`: 32 engine timeline frames, requesting 0.125 seconds per frame.
  The accepted GIF stores 0.13 seconds per frame: **4.16 seconds per loop**,
  about 7.69 fps. GIF timing is quantized; do not describe this as an exact four-second video.

These are **offscreen native engine captures**, made by SwiftUI `ImageRenderer`
and `MGCanvasRenderer`. They are not operating-system screenshots, recordings of
a complete app, browser recreations, concept art, or AI-generated images. Titles
and captions come from this example's small SwiftUI wrapper; the engine draws each board.

The static PNGs are alternatives to the repeating GIFs. GitHub controls image
playback; prefer the static gallery if you want no animation.

Every JSON scene is parsed by `MGParser` before rendering. The tree and array use
the two built-in templates. The other four use generic primitives; they do not
claim additional packs or computational services.

All example code, JSON, and captures made from them are original synthetic material
under this repository's Apache-2.0 license. System fonts are rendered using the
installed Apple SDK; no font files or third-party artwork are redistributed.

See [the showcase](../../docs/SHOWCASE.md) for the published asset inventory and
reproduction receipt. A successful `--verify` validates scenes; export and visual
quality must be checked separately.

The [committed capture receipt](../../docs/assets/native/provenance.json) records
source `7c7c280e2bde85f504a292bf09b1b8c285d295dc`, macOS 26.6.2 / Apple Swift 6.3.3
on arm64, four successful build/test/verify/export commands, 23 tests with no
failures, artifact hashes and actual stored timings. The preview window was not
launched for this receipt. Keyboard, VoiceOver, Reduce Motion, performance and
independent adopter acceptance remain pending. No video was captured.
