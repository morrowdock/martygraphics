# MartyGraphics web renderer (prototype)

**Status: prototype, not supported.** This package explores step 4 of the
[portability proposal](../../docs/PORTABILITY-PROPOSAL.md): a browser renderer that
consumes the same versioned 2D scene protocol (v1) and fixture corpus as Swift. It
claims no browser, Windows or Linux support for MartyGraphics. Swift's
`MGParser.scene(data:)` remains the authority for acceptance, and
`MGCanvasRenderer` remains the reference drawing.

It is a TypeScript port of the 2D scene path:

| Swift source (main, `5e4952e`) | Port | Scope |
| --- | --- | --- |
| [MGParser.swift](../../Sources/MartyGraphics/MGParser.swift), [MGModel.swift](../../Sources/MartyGraphics/MGModel.swift) | `src/parser.ts`, `src/primitives.ts`, `src/json.ts`, `src/model.ts` | Closed keys, limits, ranges, text rules, placeholders, references, cumulative step edits, wire form, every reason code |
| [MGTemplates.swift](../../Sources/MartyGraphics/MGTemplates.swift), [MGGraphPack.swift](../../Sources/MartyGraphics/MGGraphPack.swift) | `src/templates*.ts`, `src/pack-graphs.ts` | Parameter validation; `bst` and `two_pointers` (core); `shortest_path` (opt-in `graphs` pack) |
| [MGPatch.swift](../../Sources/MartyGraphics/MGPatch.swift) | `src/patch.ts` | Patch parsing, revisions, whole-scene revalidation |
| [MGTimeline.swift](../../Sources/MartyGraphics/MGTimeline.swift) | `src/timeline.ts`, `src/frame.ts` | Step visibility and edits, `move` motion, settled frame of a step |
| [MGLayout.swift](../../Sources/MartyGraphics/MGLayout.swift), [MGTheme.swift](../../Sources/MartyGraphics/MGTheme.swift), [MGPhysics.swift](../../Sources/MartyGraphics/MGPhysics.swift) | `src/layout.ts`, `src/theme.ts`, `src/format.ts` | Viewport, footprints, label placement, board theme, number format |
| [MGCanvasRenderer.swift](../../Sources/MartyGraphics/MGCanvasRenderer.swift) | `src/renderer.ts`, `src/gfx.ts` | Every 2D kind, focus ring, labels; emphasis rings, markers and table emphasis as API inputs |
| [SceneValidator.swift](../SceneValidator/Sources/SceneValidatorCore/SceneValidator.swift) | `src/validator.ts` | The 16 KiB raw bound (`input.too-large`) before the parser |

No runtime dependencies. TypeScript and Playwright are dev dependencies; PNG output
uses Playwright's headless Chromium with audio muted.

## Quick start

```sh
cd tools/web-renderer
npm ci
npm run build
node render.mjs ../../Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json --step last --out handoff.png
node render.mjs ../../docs/fixtures/v1/shortest-path.scene.json --pack graphs --all-steps --size 1080x1920 --scale 2 --out frames/route.png
node render.mjs ../../docs/fixtures/v1/highlight-cycle.scene.json --check   # {"status":"invalid","reason":"highlight.cycle"}, exit 1
```

`node render.mjs SCENE.json [options]` validates the scene in Node with the Swift
rules first. A refused scene prints `{"status":"invalid","reason":…}`, exits 1 and
writes nothing. Options:

| Option | Meaning |
| --- | --- |
| `--step N` / `--step last` | Step to show, 0-based. Default: the start step (0 unless a patch jumped). |
| `--all-steps` | One PNG per step: `OUT-step<N>.png`. |
| `--time T` | Seconds of motion and pulse time (default 0). The Swift stills use 1. |
| `--size WxH` | Output pixels (default `1920x1080`; `1080x1920` for portrait). |
| `--scale S` | Device pixels per point (default 1). The board is laid out at W/S × H/S points, as SwiftUI lays out a view of that size. Use 2 or 3 for video frames, so labels keep their point size. |
| `--pack graphs` | Enable the opt-in graph pack, as Showcase does. |
| `--patch FILE` | Apply a v1 patch first (repeatable, in order). |
| `--check` | Validate only and print the outcome. |

A frame is the settled state of a step, as `MartyGraphicsView` shows it once its
transitions end: step edits and visibility from `MGTimeline.items`, motion at
`--time` from `MGTimeline.frame`, the step camera (else the scene camera), the step
focus ring, and no draw-on in progress.

## Item kinds

All 19 kinds are drawn in 2D, plus the 3D-only checks (`dir` vectors, 3D kinds) in the
validator. The Swift captures in [docs/assets/native](../../docs/assets/native/provenance.json)
show only some kinds. The geometry of the others is ported line by line from
`MGCanvasRenderer.swift` but has no pixel evidence:

| Kind | Drawn | Checked against a Swift capture |
| --- | --- | --- |
| `node`, `edge` (plain, directed, labelled), `highlight` | yes | yes: tree, handoff, shortest-path, overview |
| `array` (cells, marked, pointers, label) | yes | yes: two-pointers, shortest-path |
| `text` label and callout | yes | yes: motion, two-pointers |
| `plot` | yes | yes: function |
| `bars` | yes | yes: counts |
| `path` (dashed), `body` (ball, `move` motion) | yes | yes: motion and all 32 motion GIF frames |
| `text` title and code, `body` box with angle | yes | no |
| `incline`, `line` (solid, dashed, ground hatch), `vector` (fan-out, shaft start at body edge) | yes | no |
| `axes`, `spring`, `pulley`, `rope`, `orbit` | yes | no |
| `table` (header, marked, caption, empty-table skip), `region` | yes | no |

Not ported: drawing 3D scenes (`dim: 3d` validates, then the CLI refuses with
`render.3d.unsupported`), the opt-in programmatic `layer2d` video, transitions
between steps (`MGTimeline.blend`, camera interpolation; draw-on progress exists as
the `appear` input), lessons, statement streams and explainers (separate protocols),
the opt-in geometry pack (`rotate2d`) and host-registered packs.

## Parity

### Accept, reject and reason codes

| Comparison | Inputs | Result |
| --- | --- | --- |
| Swift results (recorded 40-input `marty-scene-validate` run, `swift-cases.json`, reasons asserted by `ParserRegressionTests`, `TemplateExtensionTests` and the fixtures parsed by the Swift tests) | 239 | 239 identical |
| Swift source reading only (no Swift run): non-finite literal, five unknown keys, U+2028, line feed in a label, a plot span under 1e-6 | 5 | port follows the source |
| Python draft preflight (`tools/scene_v1_check.py` on `feat/scene-v1-json-schema`, `8882d38`) | 247 | 223 identical; 24 documented differences, in each of which the port gives Swift's result |
| Of those, every `docs/fixtures/v1` file, Showcase scene, schema-branch input and byte-boundary scene | 43 | 43 identical |
| Computed values pinned by Swift tests or printed in the Swift captures: Dijkstra narration, what-if patches and revisions, step playback, the caption and step count of all seven Showcase cards | `test/engine.unit.test.mjs` | all identical; final distances also match a Bellman-Ford oracle on 60 seeded random graphs |

The Python preflight is coarser than Swift in places (`steps` where Swift says
`step.unknown.wait`), defers template expansion (`template.build`, `hide.ref`,
`items.total`) and refuses a line feed in a title that Swift accepts. The list with
reasons is in `test/parser-python.unit.test.mjs`. The corpus (`test/corpus.mjs`) reads
`MGFixtures.swift`, `RegressionFixtures.swift` and the asserted reasons straight from
the Swift sources, so it follows them.

### Pixels and layout against the Swift captures

Swift references: the seven Showcase stills (760×440 boards, last step, t = 1 s), every
frame of the three Showcase GIFs (two-pointers and shortest-path: one per step; motion:
32 frames at t = n/8 s) and the seven 500×270 boards of `overview.png`. Each board is
located from the background colour alone and compared with this renderer's frame of the
same scene, step, time and size.

Tolerance (fixed in `scripts/parity-native.mjs`): mean absolute RGB error ≤ 6 of 255;
drawn content within 2 px both ways (recall and precision ≥ 0.95); ≥ 90% of edge tiles
(32×32, matched over ±6 px) aligned within 2 px. Tiles on the dashed focus ring are
reported apart (see the dash note below). A first per-colour centroid criterion was
dropped after the first run: colours shared by text, dashes and shapes moved by font
and dash differences, not geometry.

| Reference | Frames | Within tolerance | Worst MAE | Worst recall / precision (2 px) | Worst share of tiles within 2 px |
| --- | ---: | ---: | ---: | --- | ---: |
| `tree.png`, `handoff.png`, `function.png`, `counts.png`, `motion.png`, `shortest-path.png` | 6 | 6 | 1.35 | 0.9999 / 0.9993 | 1.00 |
| `two-pointers.png` | 1 | 0 | 1.11 | 0.997 / 0.9999 | 0.89 |
| `two-pointers.gif` | 4 | 0 | 1.69 | 0.997 / 0.9999 | 0.89 |
| `shortest-path.gif` | 8 | 8 | 1.95 | 1.00 / 1.00 | 1.00 |
| `motion.gif` | 32 | 32 | 1.12 | 1.00 / 0.9993 | 1.00 |
| `overview.png` (500×270) | 7 | 7 | 2.04 | 0.9935 / 0.9984 | 1.00 |
| **All** | **58** | **53** | | | |

The five misses are one item: the two-pointers callout. Its width follows the measured
text, and "target 14" is 65 pt wide in SF Pro Semibold but 60 pt in Segoe UI Semibold,
so the box edges sit 2.5 pt inside the Swift ones. Label placement matches even on the
crowded 500×270 boards. Node, cell, bar and curve positions agree to within a pixel.
This is tolerance-level agreement on these references, not pixel parity.

Evidence: [native-parity.json](parity/native-parity.json) (every metric per frame),
[contact-sheet-parity.png](parity/contact-sheet-parity.png) (Swift | web | difference ×4
for 30 reference frames: every still and overview board, every two-pointers and
shortest-path GIF frame, and four motion GIF frames), [contact-sheet-gallery.png](parity/contact-sheet-gallery.png)
(every other fixture frame, all steps, and the refused inputs with reasons) and
[shadow-calibration.json](parity/shadow-calibration.json). Regenerate with
`npm run parity` and `npm run contact-sheet` (full-size frames go to `out/`).

## Known gaps and uncertain geometry

- **Fonts.** Swift draws SF Pro, SF Pro Rounded and SF Mono. The browser uses its font
  stack: Segoe UI and Consolas on Windows; macOS Chromium should pick the SF faces
  (not verified). Widths come from the browser font, so labels and callouts can be a
  few points narrower and placement can shift. Line boxes use SF Pro's vertical metrics
  (1.193 em) rounded up to the pixel grid, as the captures show: a 13 pt label box is
  24 pt tall.
- **Dashed rounded rectangles.** The canvas draws circular corners from its own start
  point. The dash phase of the focus ring differs from Swift by 1–3 px along some
  sides (as few as 32% of ring tiles align within 2 px on the overview function board).
  SwiftUI's corner style for `Path(roundedRect:)` is not verified.
- **Glow.** SwiftUI shadow filters become canvas shadows with blur = 2 × radius
  (sigma = radius). The sweep of 0–2.5 against the stills put the lowest error at 2.
  The exact Core Graphics kernel is not ported.
- **Gradients and anti-aliasing** differ slightly in intensity (bar and ball fills).
  Tiles inside smooth fills carry no position information and are not judged.
- **Not verified against Swift pixels:** the kinds marked "no" above, `--scale` other
  than 1, cameras and zoom, emphasis rings, markers and table emphasis.
- **Validation corners decided without a Swift run:** duplicate object keys and a UTF-8
  byte-order mark are refused with `json`, as the Python preflight does (Swift is
  unmeasured). A `<` followed by a combining mark counts as `<`, which fails closed;
  Swift's behaviour there is pending, as the schema notes say. Canonical sizes spell
  numbers as Python does; Swift may spell very small or very large numbers differently.
  Grapheme counts come from ICU (`Intl.Segmenter`), not from Swift.
- **Ordering.** Items of one layer keep scene order, which assumes Swift's sort is
  stable (true of its current implementation, not promised by the API). Rectangles
  that only touch do not count as overlapping during label placement.

## How Studio could use it

- **Previews and stills without a Mac:** validate a lesson's scenes with the Swift
  reason codes, then render every step to PNG (`--all-steps`) for storyboards,
  thumbnails or review sheets. Use `--size 1080x1920 --scale 2` (or
  `1920x1080 --scale 2`) for video-sized frames.
- **Motion:** `move` animations are pure functions of time. Render `--time` samples
  (for example 30 per second) and assemble them with an encoder Studio already runs.
- **In a page:** `dist/browser.js` exports `render(canvas, request)`, which validates
  and draws one frame. Parsing alone (`parseSceneBytes`, `checkSceneBytes`,
  `applyPatch`) runs in Node without a browser.
- **Limits:** treat the output as a preview. Anything published as MartyGraphics output
  should still be rendered and checked natively ([VERIFY-ON-MAC](../../docs/VERIFY-ON-MAC.md)).
  Snapshot PNGs are specific to the platform's fonts: run `npm run update-snapshots`
  once on a new platform and review the images.

## Tests

`npm test` builds and runs all 603 tests in about 10 seconds:

| File | Tests | What |
| --- | ---: | --- |
| `test/parser-swift.unit.test.mjs` | 246 | Every corpus input with a Swift result (239 run on Swift, 5 from the source) |
| `test/parser-python.unit.test.mjs` | 249 | Python preflight verdicts captured in `test/expected/python-checker.json`; documented differences must match Swift |
| `test/engine.unit.test.mjs` | 15 | Number format, JSON front door, step playback, template narration, patches, wire round trip, Dijkstra oracle |
| `test/render-snapshot.render.test.mjs` | 88 | 86 frames against `test/snapshots` thumbnails (4× reduced; ≤ 0.5% of pixels may change by more than 16) |
| `test/cli.render.test.mjs` | 5 | Sizes, scale, all steps, packs, patches, fail-closed refusals, usage errors |

`npm run test:unit` skips the browser. After a renderer change, `npm run update-snapshots`
rewrites the thumbnails for review. `npm run python-results` recaptures the Python
verdicts. It needs the checker from `feat/scene-v1-json-schema`; set `MG_SCENE_CHECKER`
to its `tools/scene_v1_check.py`. The schema-branch inputs copied into the corpus are
listed in [test/corpus/schema-branch/PROVENANCE.md](test/corpus/schema-branch/PROVENANCE.md).

Evidence in this directory was produced on Windows 11 with Node 24, Playwright 1.65.1
(Chromium 159.0.8154.6 headless shell) and Python 3.13.14.
