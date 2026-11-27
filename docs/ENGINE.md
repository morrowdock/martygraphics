# The render engine

How MartyGraphics turns a checked document into pixels, what it guarantees about those pixels, and what changed in
the engine-quality pass (branch `feat/engine-quality`, from `main` at `5e4952e`). Item kinds, visual tokens, the web
renderer and the other docs pages are owned elsewhere; this page covers the render pipeline, its quality, its
performance and its exports.

**Status: pending Mac verification.** The Swift changes were written and reviewed on a machine without a Swift
toolchain. The pure algorithms (seamless-loop period and symmetry, label placement, arrow geometry, easing, preset
geometry, straight alpha) were also ported line for line to Python and run on the same golden cases, and the Blender
helpers ship with Python tests; the Swift build and the XCTests must still run on a Mac (commands at the end).

## Pipeline

```text
2D board (live view, lessons, explainer board pane)
  scene JSON ─ MGParser ─► MGScene ─ MGTimeline.items(step) ─ MGStepItemsCache (once per scene revision and step)
      ─ MGTimeline.frame(time)  motion: slide, orbit, projectile, oscillate, move
      ─ MGTween.sample          engine keyframes (true rotations, ≤ 5° apart)
      ─ MGStepTransition        step and patch changes: bounded easing, fade out, Reduce Motion dissolve
      ─► MGRenderInput (items, viewport, appear, opacity, emphasis, markers)
      ─ MGCanvasRenderer.draw(_:in:layer:)
            board + dot grid ─ items in rank order (stable) ─ rings, markers, focus ─ labels
            MGArrowGeometry (arrowheads)   MGLabelLayout (placement + leader lines)
      ─► SwiftUI Canvas in a TimelineView (MGRenderPolicy: continuous / dissolving / layered)
            layered: cached base Canvas (board, grid, static prefix) + live Canvas, MGCanvasLayers
      ─► ImageRenderer for offscreen stills (tests, lesson snapshots)

2D programmatic video (layer2d, opt-in)
  MGProgrammaticVideo.parse ─ preflight of every frame ─► MGCheckedVideoPlan
      ─ MGTimeline.videoFrame(k) ─ MGVideoDrawing (Core Graphics, sRGB) ─► CGImage per frame
      ─ MGMovieWriter (engine H.264, or an MGExportPreset) ─► MP4 / MOV      GIF: ImageIO at 10 fps

Solid 3D (assemblies, explainers)
  assembly JSON ─ MGSolidParser (strict check, gear solve, tooth phases) ─► MGSolidDocument
      ─ MGSolidRenderPlan: stills (hero, exploded, steps) + loop (one input turn, orbit, explode beat)
      ─ MGSolidLoop: exact period ─► seamless loop shots + closing shot + loop cameras
      ─ MGStoryPlan: beats, holds, camera moves, routed paths
      ─ MGSolidFraming: cameras (subject first, unblocked focus, loop framing)
      ─ MGSolidRenderer (SceneKit: PBR presets, IBL, key/fill/rim, soft shadows, SSAO, bloom, 2× supersample)
            ─ composite over the look's dithered backdrop (sRGB 8-bit) ─ MGSolidOverlayView (labels, leaders)
      ─► marty-solid render: PNG stills, loop.gif (640 px, 10 fps), loop.mp4, story.mp4, manifest.json

Offline film path
  MGSolidGLTF.renderLoop / seamlessLoop ─► .glb + manifest (martygraphics.render-export/1, optional `loop`)
      ─ tools/render-blender: manifest check ─ glTF import ─ motion proof (every object, every frame) ─ look-dev
      ─ Cycles frames (PNG) ─ MP4 (FFmpeg or NVENC), ProRes 4444, poster ─ render-report.json
```

## Quality guarantees

Each guarantee names the test that holds it. 2D tests are in `Tests/MartyGraphicsTests/RenderQualityTests.swift`,
solid tests in `Tests/MartyGraphicsTests/SolidLoopTests.swift`, export tests in
`Examples/Solid3D/Tests/MartySolidGLTFTests/SeamlessLoopExportTests.swift`, Blender tests in
`tools/tests/test_render_loop.py`.

- **Bounded transitions.** Every easing curve maps 0 to 0 and 1 to 1, stays in 0...1 and never turns back, so a
  step or patch blend keeps every coordinate between its two step values: a vector never grows past its new length,
  an angle never swings past its target and takes the short way round. Leaving items fade out from where they were.
  (`testEveryCurveIsBoundedMonotoneAndExactAtTheEnds`, `testStepTransitionsStayBetweenTheTwoStates`)
- **Reduced motion.** With Reduce Motion nothing moves: the new geometry shows at once and entering and leaving items
  cross-fade over 0.6 s; the frame loop runs for that dissolve only and never for motion.
  (`testReduceMotionDissolvesWithoutMoving`, `testDissolveAndLayerPolicyTruthTable`)
- **Labels.** In the order given, every label is placed (never dropped), at least 2 points clear of the labels placed
  before it and of their leaders, clear of obstacles, inside the bounds, on whole points. A label more than 14 points
  from its anchor gets a leader from the anchor to the nearest point of its box; a leader crosses no other label, no
  other leader and no obstacle except the one its anchor sits on. The same input gives the same layout.
  (`testCrowdedLabelsNeverOverlapAndFarOnesPointBack`, `testAFreeLabelSitsInItsOwnDirectionWithoutALeader`)
- **Arrowheads.** The head is 3.5 line widths + 3 points (7...16) and never more than 45 % of the arrow, so a short
  arrow, and every arrow while it draws on from length 0, keeps its proportions; the shaft never points backwards,
  ends under the head and, when dashed, ends on a whole dash. (`testArrowHeadsKeepTheirProportions`)
- **Layers.** While motion plays, the board, the grid and the static items drawn below every moving item are drawn
  once; the live layer redraws the rest each frame. The two layers keep one frame's draw order and composite to that
  frame within rounding. (`testTheBaseLayerIsTheStaticPrefixOfTheDrawOrder`,
  `testTheTwoLayersCompositeToTheOneCanvasFrame`)
- **Seamless loops.** A seamless loop plays the exact period of the motion: every driven joint turns a whole number
  of the symmetry steps of what it carries, measured on the meshes (never assumed) and checked on every moving part's
  vertices. The change from the last frame to the first equals the motion's own step (within 1e-7°), the loop camera
  repeats, and no part's own pattern advances more than 0.4 of its symmetry step a frame (no wagon-wheel reversal).
  (`testTheSeamlessPlanHasNoJumpAtTheWrap`, `testTheSeamlessExportHasNoJumpAtTheWrap`)
- **Export presets.** A preset that cannot be written is refused before any frame (odd size for 4:2:0, alpha on
  H.264, a safe area that leaves nothing); frames of another size are fitted, centred, on whole pixels; the colour
  tags match the pixels; straight alpha divides every colour by its alpha. Frame k is presented at k / fps.
  (`testPresetsAreWritableAndTaggedForTheirDestination`, `testAPresetWriterWritesItsFrameRateAndTags`,
  `testStraightAlphaUndoesPremultiplication`, `testA2DVideoExportsWithAPreset`)
- **Unchanged outputs.** The default render loop, `marty-solid render`, the default `export-gltf` output and the
  engine's own MP4 settings are unchanged; the new paths are opt-in (`--seamless`, `MGExportPreset`). The existing
  goldens still apply.

## Seamless loops

The render loop plays one input turn in 12 s. A part that turns a fraction of a turn per input turn does not come
back to where it started, so the loop jumps at the wrap. On the AI-written robot-joint reducer
([its JSON](assets/from-a-prompt/robot-joint/robot-joint-gearbox.json)) the output carrier turns 4/49 of a turn per
input turn: at 30 fps (360 frames) it advances 0.0816° a frame and then turns 29.306° back from the last frame to the
first. `testTheRenderLoopOfTheRobotJointJumpsAtTheWrap` reproduces those numbers.

`MGSolidLoop.period` finds the exact period:

1. **Exact rates.** Every driven joint is classified from its drive graph: still, linear in the input (input,
   follow and gear drives, and every gear-mesh solve, which the parser stores as `input(scale:offset:)`), periodic in
   a crank (crank-slider and crank-rod drives and what follows them) or mixed (refused, `mixed`). A linear joint's
   rate is turned into an exact fraction with q ≤ 100 000 (`ratio` when there is none). A slide that moves steadily
   with the input never comes back (`slide`).
2. **Measured symmetry.** For each turning joint, the points of what it turns (its part and every part carried by
   it, in its frame) are reduced to features: a ring of at least 24 evenly spaced vertices about a part's own axis is
   a tessellated circle and is replaced by its centre, so a 72-segment bore does not hide the symmetry of a
   23-tooth gear. The candidate order is the gcd of the ring sizes about the joint axis, and the largest divisor whose
   rotation maps the points onto themselves (same material, within 1e-6 of the model's size) is the order.
3. **The lattice.** Joint i must turn a whole number of 1/sᵢ turns: L × rateᵢ × sᵢ ∈ ℤ for every i, and a crank must
   come back to its own angle. The smallest such L is lcm(denominators) / gcd(numerators) of the products.
4. **The check.** The feature points of every drawn moving part at the start input and L input turns later must
   coincide (same material). If they do not, the analysis falls back to whole turns of every joint (`strict`), and
   refuses (`check`) only if that also fails. A period longer than `maxTurns` (64) is refused (`period`).

For the robot joint the measured orders are sun 24, both carriers 3 (arms, pins and planets), planets 18, so
L = lcm(1, 7, 7, 49, 49) / gcd(24, 6, 120, 12, 240) = **49/6 input turns**: the sun turns 8 1/6 turns (4 teeth on)
and the output carrier 2/3 of a turn (two arms on). Without symmetry it would be 147 input turns.

`MGSolidLoop.plan` samples the period with frame k at k / n of it, so frame n would be frame 0 again. n is the
largest of the minimum duration (12 s), the frame bound (the fastest own pattern moves at most 0.4 of its symmetry
step a frame; the robot joint's sun passes 196 teeth, so 490 frames, 16.3 s at 30 fps) and a multiple of
`frameMultiple`; a loop longer than `maxSeconds` (60 s) is refused (`frames`). The plan keeps the render loop's orbit
and explode beat, so a mechanism whose period is one turn gets exactly the render loop. `MGSolidLoop.cameras` frames
every frame at the start input (the render loop's framing follows turned parts' bounding boxes and would jump at the
wrap), then moves every camera back by one factor until every frame's real pose fits.

`marty-solid export-gltf FILE.json NEW_DIR --engine-commit SHA --seamless` writes that loop plus a **closing frame**
(frame n, the motion continued) and a `loop` object in the manifest:
`{"seamless": true, "frames": n, "closingFrame": n, "inputTurns": "49/6", "seconds", "stepsPerFrame", "joints"}`.
The [Blender render path](../tools/render-blender/README.md) then renders frames 0...n−1 only, opens the
motion-blur shutter at the frame (so the last frame blurs toward the closing key exactly as frame 0 blurs toward
frame 1), completes a turntable at frame n, and sways its automatic camera out and back instead of sweeping one way.
Refusals: `gltf.loop.<reason>` with the reasons above, and the exporter's own `gltf.fps`, `gltf.size`, `gltf.frames`.

## Export presets

`MGExportPreset` gives one destination's frame, rate, codec, bit rate, key frames, colour handling, alpha and safe
area. `MGMovieWriter(url:preset:)` writes with one; `MGVideoExportOptions(preset:)` uses one for a 2D video.

| Preset | Frame | Codec | Bit rate | Key frame | Colour | Alpha | Longest | Safe area (top, left, bottom, right) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `shorts` | 1080 × 1920, 30 fps | H.264 High | 12 Mbit/s | 0.5 s | BT.709 tags | none | 180 s | 10 %, 6 %, 22 %, 18 % |
| `x` | 1920 × 1080, 30 fps | H.264 High | 16 Mbit/s | 1 s | BT.709 tags | none | 140 s | 5 %, 5 %, 12 %, 5 % |
| `lesson` | 1920 × 1200, 30 fps | H.264 High | 14 Mbit/s | 2 s | sRGB transfer tag | none | none | none |
| `lesson-alpha` | 1920 × 1200, 30 fps | ProRes 4444 (MOV) | quality | every frame | sRGB transfer tag | straight | none | none |
| `shorts-alpha` | 1080 × 1920, 30 fps | ProRes 4444 (MOV) | quality | every frame | BT.709 tags | straight | none | as `shorts` |

Colour: the engine draws sRGB. `srgb` keeps the pixels and tags BT.709 primaries and matrix with the sRGB transfer
function (Apple players then show the video as the stills); `rec709` keeps the pixels and tags BT.709 throughout, the
tags upload transcoders read; `displayP3` converts the pixels to Display P3 and tags P3-D65 primaries. Alpha: H.264
and HEVC carry none; ProRes 4444 stores straight alpha (`straight`, what most editors read) or the buffer's
premultiplied colours (`premultiplied`). No preset reorders frames, so frame k is presented at k / fps and a video of
n frames lasts exactly n / fps.

## Audit

Findings at `5e4952e` (`file:line` there), with what this branch did.

| # | Area | Finding | Where | Status |
| --- | --- | --- | --- | --- |
| 1 | 3D loop | The loop is one input turn; parts with a fractional ratio jump at the wrap (robot joint: 0.082° a frame, then 29.306° back). The glTF export bakes the same loop. | `Sources/MartyGraphics/Solid/MGSolidRenderPlan.swift:80`, `:84`; `Examples/Solid3D/Sources/MartySolidGLTF/MGSolidGLTF.swift:113` | Fixed: `MGSolidLoop`, `export-gltf --seamless` |
| 2 | Video path | Blender's centred shutter samples before key 0 and after the last key, so the first and last frames blur half; the automatic camera sweeps one way and jumps back when the video loops. | `tools/render-blender/mgrender/lookdev.py:477`, `:405` | Fixed for seamless exports (closing key, START shutter, sway) |
| 3 | Timing | Step blends, camera moves and draw-on pops use a spring that overshoots by about 12 % (a vector longer than its new length, an angle past its target) and ends on a step at 1.2 s. | `Sources/MartyGraphics/MartyGraphicsView.swift:429`, `:436`; `Sources/MartyGraphics/MGCanvasRenderer.swift:77`, `:250`; `Sources/MartyGraphics/MGTimeline.swift:135` | Fixed: `MGEasing`, `MGStepTransition` |
| 4 | Timing | Items that leave a step vanish at once; with Reduce Motion there is no transition at all and the frame loop never runs. | `Sources/MartyGraphics/MartyGraphicsView.swift:429`; `Sources/MartyGraphics/MGRenderPolicy.swift:26` | Fixed: fade out, dissolve, `MGRenderPolicy.dissolving` |
| 5 | Text | Greedy placement with a least-overlap fallback and no leader lines: a pushed-away label loses its anchor; boxes sit on fractional points. | `Sources/MartyGraphics/MGLayout.swift:122`; `Sources/MartyGraphics/MGCanvasRenderer.swift:299` | Fixed: `MGLabelLayout` |
| 6 | Arrows | The head (7...14 points) is longer than a short arrow, so while an arrow draws on its head reaches behind the tail and the shaft is stroked backwards; a dashed shaft can end in a gap; 2D-video shafts are stroked to the tip, so the line end shows past the sharp head. | `Sources/MartyGraphics/MGCanvasRenderer.swift:345`, `:347`, `:355`; `Sources/MartyGraphics/MGVideoDrawing.swift:155` | Fixed: `MGArrowGeometry` |
| 7 | Performance | Every 2D frame re-applies every step's edits, and the whole board (gradient, dot grid, every item with its shadow layers) redraws at 60 Hz while anything moves. | `Sources/MartyGraphics/MartyGraphicsView.swift:426`, `:282`; `Sources/MartyGraphics/MGTimeline.swift:44` | Fixed: `MGStepItemsCache`, cached base layer |
| 8 | Performance | `setCamera` rebuilds the ground, the contact blob and two 256 × 256 alpha images on every call, so once per loop and story frame, although they depend only on the default pose. | `Sources/MartyGraphics/Solid/MGSolidRenderer.swift:492`, `:824`, `:855` | Fixed: rebuilt only when the bounds change |
| 9 | Export | One H.264 profile (0.2 bit per pixel, 2 s key frames) tagged with the sRGB transfer function only: no destination presets, no BT.709 or P3 option, no alpha; pooled buffers are drawn over without clearing. | `Sources/MartyGraphics/MGMovieWriter.swift:27`, `:34`, `:38`, `:112` | Fixed: `MGExportPreset`, buffers cleared |
| 10 | Hairlines | 1-point lines and 2-point dots at fractional positions blur at 1x and 3x (table grid, plot grid, label borders, board dots). | `Sources/MartyGraphics/MGCanvasRenderer.swift:468`, `:394`, `:304`, `:336` | Fixed: half-point lines, whole-point dots and boxes |
| 11 | 3D loop | The loop camera is framed on each frame's turned parts' bounding-box corners, so it breathes as parts turn. | `Sources/MartyGraphics/Solid/MGSolidFraming.swift:469`, `:476` | Fixed for seamless loops (`MGSolidLoop.cameras`); the render loop is unchanged |
| 12 | Colour | The CLI's caption, title and GIF-scale contexts use device RGB, not sRGB, so stills and GIF frames are converted into a device space. | `Examples/Solid3D/Sources/MartySolidCLI/main.swift:302`, `:352`, `:471`, `:481`, `:490` | Open: use sRGB (changes published pixels) |
| 13 | Colour | Blender's NVENC encode tags BT.709 transfer on sRGB-encoded frames; its FFmpeg encode writes no tags. | `tools/render-blender/render.py:562`, `:330` | Open |
| 14 | Text | Board labels are a fixed 13 points at every board size; text items are bounded by a 0.56 em per character estimate, not measured text. | `Sources/MartyGraphics/MGCanvasRenderer.swift:70`, `:305`; `Sources/MartyGraphics/MGLayout.swift:91` | Open |
| 15 | Text | 2D video text is hard-coded Helvetica and Menlo. | `Sources/MartyGraphics/MGVideoDrawing.swift:8` | Open |
| 16 | 3D | Arrow and dimension cylinders have a radius that is a share of the model, with no minimum pixel width: thin pieces shimmer in the 640-pixel GIF. | `Sources/MartyGraphics/Solid/MGSolidAnnotations.swift:38` | Open |
| 17 | 3D | Texture coordinates use u = 8 · atan2(y, x), which jumps at ±π; harmless for today's streaks (constant along u), a seam for any texture that varies along u. | `Sources/MartyGraphics/Solid/MGSolidRenderer.swift:957` | Open |
| 18 | Performance | Every label is resolved and measured each frame and resolved again to draw; highlights and edges resolve references with linear scans (quadratic per frame); fans regroup vectors each frame; the 3D view builds its signature from the canonical source on every update. | `Sources/MartyGraphics/MGCanvasRenderer.swift:70`, `:305`, `:59`; `Sources/MartyGraphics/MGLayout.swift:40`, `:84`; `Sources/MartyGraphics/MG3DView.swift:139` | Open |
| 19 | Determinism | The draw order relied on the standard sort being stable. | `Sources/MartyGraphics/MGCanvasRenderer.swift:62` | Fixed: explicit stable order |
| 20 | Export | Frame-exact durations hold: frame k at k / fps, the session ends at n / fps, no B-frames. | `Sources/MartyGraphics/MGMovieWriter.swift:38` | Kept, and in every preset |
| 21 | Text | Baseline and kerning are consistent: the Core Text paths centre a line on (ascent − descent) / 2, the canvas centres SwiftUI text on its box, every path keeps the font's own kerning and only the CLI title tracks tighter (−0.2 px × scale). Small labels get no extra tracking. | `Sources/MartyGraphics/MGVideoDrawing.swift:67`; `Sources/MartyGraphics/Solid/MGSolidOverlayView.swift:108`; `Examples/Solid3D/Sources/MartySolidCLI/main.swift:427` | Kept |
| 22 | Timing | Frame pacing: the 2D loop runs at 60 Hz on the wall clock or the session's presentation clock, and only while something moves or a transition runs; 120 Hz is not requested. | `Sources/MartyGraphics/MGRenderPolicy.swift:39`; `Sources/MartyGraphics/MartyGraphicsView.swift:282` | Kept (plus the dissolve under Reduce Motion) |
| 23 | 3D | Lighting, materials and shadows hold up: a procedural studio environment in extended linear sRGB, PBR presets, a 4096-pixel key shadow map with 24 soft samples fitted to the exploded bounds, ambient occlusion that follows the camera distance and a dithered backdrop. | `Sources/MartyGraphics/Solid/MGSolidRenderer.swift:898`, `:807`, `:839`, `:486`; `Sources/MartyGraphics/Solid/MGSolidLook.swift:182` | Kept |

## Before → after

- Turntable and mechanism loops: one input turn with a jump at the wrap → the exact period (robot joint 49/6 input
  turns, 490 frames at 30 fps) with a wrap step equal to every other step, a repeating camera and a closing frame.
- Blender video of a seamless export: half-blurred first and last frames and a one-way camera → motion blur that
  continues across the wrap and a turntable or sway that closes.
- Step changes: an overshooting spring, instant exits, nothing under Reduce Motion → bounded quintic easing in 0.6 s,
  fading exits, a dissolve under Reduce Motion.
- Body and node pops: 12 % overshoot, never exactly full size → a critically damped approach that lands on the size.
- Labels: 36 positions and overlap as a fallback → 72 positions, leader lines, no label over a leader, whole points.
- Arrowheads: reversed shafts and oversized heads on short arrows, floating dashed heads → proportional heads, a shaft
  under the head, whole dashes.
- Live 2D board while motion plays: everything at 60 Hz and every step edit re-applied per frame → a cached base
  layer and cached step items.
- Solid renderer: ground rebuilt per frame → built once per pose bounds.
- Video export: one H.264 setting → Shorts, X and lesson presets with BT.709, sRGB or P3 handling and ProRes 4444
  straight alpha; pooled frames cleared.
- Hairlines: blurry 1-point lines at 1x and 3x → lines on the half-point grid, crisp at 1x, 2x and 3x.

## Verify on a Mac

From the repository root on macOS 14+ with Xcode 26 (see [Verify on Mac](VERIFY-ON-MAC.md)):

```sh
swift build
swift test --filter 'MartyGraphicsTests.(SolidLoopTests|RenderQualityTests)'
swift test                                                   # the whole engine suite, goldens included
swift test --package-path Examples/Solid3D --filter 'MartySolidGLTFTests'
swift test --package-path Examples/Solid3D                   # CLI goldens and the rest
python3 -m unittest discover -s tools/tests -v
B=$(swift build -c release --package-path Examples/Solid3D --show-bin-path)
swift build -c release --package-path Examples/Solid3D
$B/marty-solid export-gltf docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json /tmp/rj-seamless \
  --engine-commit "$(git rev-parse HEAD)" --seamless
python3 -c "import json; m = json.load(open('/tmp/rj-seamless/robot-joint-gearbox.manifest.json')); print(m['frameCount'], m['loop'])"
```

The last command should print `491` and a `loop` object with `"frames": 490` and `"inputTurns": "49/6"`. Then, on
the Linux render host of the [Blender render path](../tools/render-blender/README.md) (after its `setup.sh`), render
the copied export as a turntable and watch the wrap; the log names the seamless loop and `render-report.json` records
`"motion_blur_position": "START"` and 490 rendered frames:
`blender -b --factory-startup -P tools/render-blender/render.py -- rj-seamless/robot-joint-gearbox.manifest.json rj-film --turntable`.
