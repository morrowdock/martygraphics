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

The corpus (`test/corpus.mjs`) has 247 inputs. None of the comparisons below ran Swift
for this change: the Swift side is either a recorded result or an expectation read from
the Swift sources.

| Comparison | Inputs | Result |
| --- | --- | --- |
| Recorded Swift results: the 40-input `marty-scene-validate` run transcribed from `SWIFT-PARITY.md` and `swift-cases.json` on `feat/scene-v1-json-schema` (`8882d38`), not re-run here | 40 | 40 identical |
| Expectations derived from the Swift test sources: reasons asserted by `ParserRegressionTests` (160) and `TemplateExtensionTests` (24), and the `MGFixtures` (6) and `RegressionFixtures` (9) scenes the Swift tests parse | 199 | 199 identical |
| Swift source reading only (no recorded result, no test): non-finite literal, five unknown keys, U+2028, line feed in a label, a plot span under 1e-6 | 5 | port follows the source |
| Python draft preflight (`tools/scene_v1_check.py` on `feat/scene-v1-json-schema`, `8882d38`), verdicts captured in `test/expected/python-checker.json` | 247 | 223 identical, 24 differ |
| The 24 differences: 18 map to `ParserRegressionTests` assertions, 1 to the `TemplateExtensionTests` reason table, 5 are the source-reading probes above | 24 | the port gives the Swift expectation in each |
| Of the 247, every `docs/fixtures/v1` file, Showcase scene, schema-branch input and byte-boundary scene | 43 | 43 identical to Python |
| Computed values pinned by Swift tests or printed in the Swift captures: Dijkstra narration, what-if patches and revisions, step playback, the caption and step count of all seven Showcase cards | `test/engine.unit.test.mjs` | all identical; final distances also match a Bellman-Ford oracle on 60 seeded random graphs |

So 239 results are recorded or test-derived and 5 rest on reading the source. Swift
tests and `marty-scene-validate` would need a Mac to re-run.

The Python preflight is coarser than Swift in places (`steps` where Swift says
`step.unknown.wait`), defers template expansion (`template.build`, `hide.ref`,
`items.total`) and refuses a line feed in a title that Swift accepts. The list with
reasons is in `test/parser-python.unit.test.mjs`. The corpus reads `MGFixtures.swift`,
`RegressionFixtures.swift` and the asserted reasons straight from the Swift sources,
so it follows them.

Outside this claim: duplicate object keys and a UTF-8 byte-order mark. No Swift result
or Swift test covers them; the port refuses both with `json`, as the Python preflight
does (see "Validation corners" below).

### Pixels and layout against the Swift captures

Swift references: the seven Showcase stills (760×440 boards, last step, t = 1 s), every
frame of the three Showcase GIFs (two-pointers and shortest-path: one per step; motion:
32 frames at t = n/8 s) and the seven 500×270 boards of `overview.png`. Each board is
located from the background colour alone and compared with this renderer's frame of the
same scene, step, time and size.

One function measures a frame and one rule judges it: `measureFrame` and `verdict` in
`web/pixels.js`. The parity report (`scripts/parity-native.mjs`), the contact sheet
(`scripts/contact-sheet.mjs`) and `test/parity-metric.render.test.mjs` all call them.

Tolerance (`TOLERANCE` in `web/pixels.js`): mean absolute RGB error ≤ 6 of 255; drawn
content within 2 px both ways (recall and precision ≥ 0.95); ≥ 90% of judged edge tiles
(32×32, matched over ±6 px) aligned within 2 px; and every judged tile's best match
scores at least 0.85. The match score is the share of the Swift tile's edge pixels that
have an edge pixel in the web tile within 1 px, at the best shift. A tile counts as
aligned only if its shift is ≤ 2 px and its score is ≥ 0.85. Tiles on the dashed focus
ring are reported apart and not judged (see the dash note below). A frame with no judged
tiles, or with no drawn content on either side, fails. A first per-colour centroid
criterion was dropped after the first run: colours shared by text, dashes and shapes
moved by font and dash differences, not geometry.

| Reference | Frames | Within tolerance | Worst MAE | Worst recall / precision (2 px) | Worst share of tiles within 2 px | Lowest tile score |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| `tree.png`, `handoff.png`, `function.png`, `counts.png`, `motion.png`, `shortest-path.png` | 6 | 6 | 1.35 | 0.9999 / 0.9993 | 1.00 | 0.95 |
| `two-pointers.png` | 1 | 0 | 1.11 | 0.997 / 0.9999 | 0.89 | 0.89 |
| `two-pointers.gif` | 4 | 0 | 1.69 | 0.997 / 0.9999 | 0.89 | 0.89 |
| `shortest-path.gif` | 8 | 8 | 1.95 | 1.00 / 1.00 | 1.00 | 0.89 |
| `motion.gif` | 32 | 32 | 1.12 | 1.00 / 0.9993 | 1.00 | 1.00 |
| `overview.png` (500×270) | 7 | 7 | 2.04 | 0.9935 / 0.9984 | 1.00 | 0.89 |
| **All** | **58** | **53** | | | | |

The five misses are one item: the two-pointers callout. Its width follows the measured
text, and "target 14" is 65 pt wide in SF Pro Semibold but 60 pt in Segoe UI Semibold,
so the box edges sit 2.5 pt inside the Swift ones. Label placement matches even on the
crowded 500×270 boards. Node, cell, bar and curve positions agree to within a pixel.
This is tolerance-level agreement on these references, not pixel parity.

Negative controls (`scripts/parity-cases.mjs`) are valid scenes rendered wrong on
purpose and compared with the unchanged Swift capture. Both must fail, and do:

| Control | MAE | Recall / precision | Tiles within 2 px | Lowest tile score | Verdict |
| --- | ---: | --- | ---: | ---: | --- |
| `motion.png` without the small "B" text item | 0.53 | 0.975 / 1.00 | 0.91 | 0.00 | fail |
| `handoff.png` with the label "Queue" changed to "Store" | 1.10 | 1.00 / 1.00 | 0.97 | 0.81 | fail |

Both controls pass every other check: only the tile score catches them. The margins are
thin. The lowest tile score on a frame that passes is 0.89 (SF Pro against Segoe UI
text), and the changed label scores 0.81, either side of the 0.85 floor.

What the metric can detect, on these references:

- An item moved by more than 2 px, where its tile has edge structure.
- A missing item or glyph that holds more than 15% of the edge pixels of a judged tile
  (a 32×32 tile with at least 24 strong edge pixels in the Swift capture): the "B"
  control.
- Different text of similar size and position, when the glyph shapes differ enough
  (the "Queue"/"Store" control, by a small margin).
- Large added, missing or recoloured areas, through recall, precision and mean error.

What it cannot detect:

- Small content added to the web frame only. Tiles are cut from the Swift capture, so
  extra content shows up only through precision and mean error.
- Changes inside flat fills or smooth gradients (tiles with too few edges are skipped),
  colour or opacity changes below the mean-error tolerance, and anything on the
  excluded focus-ring band.
- A one-character change between similar glyphs: font differences already lower text
  tiles to about 0.89, so the floor cannot be raised much further.
- Kinds, scales, cameras and steps with no Swift capture (see "Item kinds").

Evidence: [native-parity.json](parity/native-parity.json) (every metric per frame, the
negative controls and the verdict reasons),
[contact-sheet-parity.png](parity/contact-sheet-parity.png) (Swift | web | difference ×4
for 30 reference frames: every still and overview board, every two-pointers and
shortest-path GIF frame, and four motion GIF frames, each with the report's verdict and
both the judged and the excluded focus-ring tile scores),
[contact-sheet-gallery.png](parity/contact-sheet-gallery.png) (every other fixture
frame, all steps, and the refused inputs with reasons) and
[shadow-calibration.json](parity/shadow-calibration.json) (the blur sweep over the 14
PNG boards, keyed by frame). Regenerate with `npm run parity`,
`node scripts/parity-native.mjs --calibrate` and `npm run contact-sheet` (full-size
frames go to `out/`). The evidence images and snapshots come from Windows with
Playwright's Chromium only.

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
  (sigma = radius). The sweep of 0–2.5 against the 14 PNG boards (seven stills, seven
  overview boards) put the lowest mean error at 2. A `shadowBlurPerRadius` override in
  a render request applies to that render only.
  The exact Core Graphics kernel is not ported.
- **Gradients and anti-aliasing** differ slightly in intensity (bar and ball fills).
  Tiles inside smooth fills carry no position information and are not judged.
- **Not verified against Swift pixels:** the kinds marked "no" above, `--scale` other
  than 1, cameras and zoom, emphasis rings, markers and table emphasis.
- **Validation corners decided without a Swift run** (outside the parity claim above):
  duplicate object keys and a UTF-8 byte-order mark are refused with `json`, as the
  Python preflight does. Swift's behaviour is unmeasured and no Swift fixture covers
  them yet. A `<` followed by a combining mark counts as `<`, which fails closed;
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

`npm test` builds and runs all 612 tests in about 10 seconds:

| File | Tests | What |
| --- | ---: | --- |
| `test/parser-swift.unit.test.mjs` | 246 | Every corpus input with a Swift expectation: 40 recorded results, 199 from the Swift test sources, 5 from reading the source |
| `test/parser-python.unit.test.mjs` | 250 | Python preflight verdicts captured in `test/expected/python-checker.json`; each of the 24 documented differences must give the Swift expectation |
| `test/engine.unit.test.mjs` | 16 | Number format, JSON front door, step playback, template narration, patches, wire round trip, Dijkstra oracle, a refused render keeps the shadow calibration |
| `test/render-snapshot.render.test.mjs` | 88 | 86 frames against `test/snapshots` thumbnails (4× reduced; ≤ 0.5% of pixels may change by more than 16) |
| `test/cli.render.test.mjs` | 5 | Sizes, scale, all steps, packs, patches, fail-closed refusals, usage errors |
| `test/parity-metric.render.test.mjs` | 7 | The shared parity metric: unchanged scenes pass, both negative controls fail, missing evidence fails, a shadow override lasts one render |

`npm run test:unit` skips the browser. After a renderer change, `npm run update-snapshots`
rewrites the thumbnails for review. `npm run python-results` recaptures the Python
verdicts. It needs the checker from `feat/scene-v1-json-schema`; set `MG_SCENE_CHECKER`
to its `tools/scene_v1_check.py`. The schema-branch inputs copied into the corpus are
listed in [test/corpus/schema-branch/PROVENANCE.md](test/corpus/schema-branch/PROVENANCE.md).

Evidence in this directory was produced on Windows 11 with Node 24, Playwright 1.65.1
(Chromium 159.0.8154.6 headless shell) and Python 3.13.14.
