# The render engine

How MartyGraphics turns a checked document into pixels, what it guarantees about those pixels, and what changed in
the engine-quality pass (branch `feat/engine-quality`, from `main` at `5e4952e`). Item kinds, visual tokens, the web
renderer and the other docs pages are owned elsewhere; this page covers the render pipeline, its quality, its
performance and its exports.

**Status: pending Mac verification.** The Swift changes were written and reviewed on a machine without a Swift
toolchain: no Swift on this branch has been built or run, and every Swift test named on this page is unrun. What did
run is Python only: `tools/tests/test_render_loop.py` tests the Blender loop helpers (`mgrender/loop.py`) and the
manifest check with hand-built manifest records and analytic expectations. It does not read Swift output, so it is not
a parity check of the Swift code; the Swift goldens in the XCTests (49/6 input turns, 490 frames, label boxes, arrow
lengths) are derived by hand. The Mac command list at the end builds and runs everything, and generates the Swift
vectors (the robot joint's seamless manifest) for a later Python parity test.

## Pipeline

```text
2D board (live view, lessons, explainer board pane)
  scene JSON ─ MGParser ─► MGScene ─ MGTimeline.items(step) ─ MGTimelineCache (once per scene revision and step)
      ─ MGTimeline.frame(time)  motion: slide, orbit, projectile, oscillate, move
      ─ MGTween.sample          engine keyframes (true rotations, ≤ 5° apart)
      ─ MGBoardTransition       step and patch changes by MGTransitionStyle: .spring (the default, unchanged)
                                or .bounded (opt-in: MGStepTransition, fade out, Reduce Motion dissolve)
      ─► MGRenderInput (items, viewport, appear, opacity, emphasis, markers)
      ─ MGCanvasRenderer.draw(_:in:layer:)
            board + dot grid ─ items in rank order (stable) ─ rings, markers, focus ─ labels
            MGArrowGeometry (arrowheads)   MGLabelLayout (placement + leader lines)
      ─► SwiftUI Canvas in a TimelineView (MGRenderPolicy: continuous; dissolving for .bounded only; layered)
            layered: base Canvas outside the TimelineView (board, grid, static prefix) + live Canvas, MGCanvasLayers
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

- **Transitions: the spring by default, bounded on request.** A board without `transitionStyle(_:)` moves exactly as
  at `5e4952e` (see [Transitions](#transitions)). On a board with `transitionStyle(.bounded)`, every easing curve maps
  0 to 0 and 1 to 1, stays in 0...1 and never turns back, so a step or patch blend keeps every coordinate between its
  two step values: a vector never grows past its new length, an angle never swings past its target and takes the
  short way round, and leaving items fade out from where they were. (`BoardTransitionTests`,
  `BoardTransitionHostTests`, `testEveryCurveIsBoundedMonotoneAndExactAtTheEnds`,
  `testStepTransitionsStayBetweenTheTwoStates`)
- **Reduced motion.** By default the board snaps: with Reduce Motion a step or patch shows the new state at once, with
  no blend, no dissolve and no frame loop. A `.bounded` board dissolves instead: nothing moves, entering and leaving
  items cross-fade over 0.6 s, and the frame loop runs for that dissolve only and never for motion.
  (`testWithReduceMotionTheDefaultBoardSnapsAndNeverTicks`, `testWithReduceMotionTheBoundedBoardTicksOnlyDuringTheDissolve`,
  `testOnlyABoundedBoardRunsTheLoopForAReduceMotionDissolve`, `testReduceMotionDissolvesWithoutMoving`,
  `testDissolveAndLayerPolicyTruthTable`)
- **Labels.** In the order given, every label is placed (never dropped), at least 2 points clear of the labels placed
  before it and of their leaders, clear of obstacles, inside the bounds, on whole points. A label more than 14 points
  from its anchor gets a leader from the anchor to the nearest point of its box; a leader crosses no other label, no
  other leader and no obstacle except the one its anchor sits on. The same input gives the same layout.
  (`testCrowdedLabelsNeverOverlapAndFarOnesPointBack`, `testAFreeLabelSitsInItsOwnDirectionWithoutALeader`)
- **Arrowheads.** The head is 3.5 line widths + 3 points (7...16) and never more than 45 % of the arrow, so a short
  arrow, and every arrow while it draws on from length 0, keeps its proportions; the shaft never points backwards,
  ends under the head and, when dashed, ends on a whole dash. (`testArrowHeadsKeepTheirProportions`)
- **Layers.** While motion plays and no transition runs, the board draws a base canvas under a live canvas (see
  [Layers and caches](#layers-and-caches) for exactly what the base holds and when it is redrawn). For one input, the
  two layers keep one frame's draw order and composite to that frame within rounding
  (`testTheBaseLayerIsTheStaticPrefixOfTheDrawOrder`, `testTheTwoLayersCompositeToTheOneCanvasFrame`). That this
  holds on a live board across ticks and changes is what `testTheSplitBoardStaysExactAcrossTicksAndChanges` checks;
  until it passes on a Mac, no more than the one-input claim is made.
- **Seamless loops.** A seamless loop plays the exact period of the motion: every driven joint turns a whole number
  of the symmetry steps of what it carries, measured on the meshes (never assumed) and checked on every moving part's
  vertices. The change from the last frame to the first equals the motion's own step (within 1e-7°), the loop camera
  repeats, and no part's own pattern advances more than 0.4 of its symmetry step a frame (no wagon-wheel reversal).
  (`testTheSeamlessPlanHasNoJumpAtTheWrap`, `testTheSeamlessExportHasNoJumpAtTheWrap`)
- **Export presets.** A preset that cannot be written is refused before any frame (odd size for 4:2:0, alpha on
  H.264, a safe area that leaves nothing); frames of another size are fitted, centred, on whole pixels; straight alpha
  divides every colour by its alpha. Frame k is presented at k / fps. Colour: **tags requested; decoded check
  pending** (`testColourPatchesDecodeAsTheirTagsSay`). Alpha: the 2D alpha export leaves the canvas clear where
  nothing is drawn; that the decoded ProRes 4444 is `ap4h`, clear there and correctly straight on half-transparent
  shapes and edges is pending (`testTheAlphaMasterIsClearWhereNothingIsDrawn`).
  (`testPresetsAreWritableAndTaggedForTheirDestination`, `testAPresetWriterWritesItsFrameRateAndTags`,
  `testStraightAlphaUndoesPremultiplication`, `testA2DVideoExportsWithAPreset`)
- **Outputs.** The 2D board's transitions, the default render loop, `marty-solid render`, the default `export-gltf`
  output and the engine's own MP4 encoder settings are unchanged; the new paths are opt-in (`transitionStyle(.bounded)`,
  `--seamless`, `MGExportPreset`). Four pure fixes change default pixels on purpose; they are listed in
  [Default output changes](#default-output-changes), with stills to compare.

## Transitions

`MartyGraphicsView.transitionStyle(_:)` picks how a 2D board moves between steps and patches (`MGTransitionStyle`).
The pure decisions are `MGBoardTransition`; the board host and the renderer call them on every frame.

| | `.spring` (default) | `.bounded` (opt-in) |
| --- | --- | --- |
| Step and patch blend | `MGTimeline.blend` at `MGTimeline.spring(t)` for 1.2 s (the spring overshoots by about 12 %) | `MGStepTransition`: quintic smootherstep over 0.6 s, no value past either step |
| Camera move on a step | `MGTimeline.spring(t)` for 1.0 s | 0.8 s on the same curve as the blend |
| Body and node draw-on pop | `MGTimeline.spring(p · 0.9)` (overshoots, rests just under the size) | `MGEasing.Curve.settle` (lands exactly on the size) |
| Items that leave | vanish at once | fade out from where they were |
| Reduce Motion | snaps: the new state at once, no frame loop | dissolves: nothing moves, items cross-fade over 0.6 s, the loop runs for the dissolve only |

`MGRenderInput.transitionStyle` (default `.spring`) carries the pop choice to the renderer, so every other host of
`MGCanvasRenderer` (lesson snapshots, explainer panes) keeps the spring pops. The lesson and explainer views embed the
default board, so they keep the spring too.

## Layers and caches

While motion plays and no transition runs (`MGRenderPolicy.layered`), a 2D board without a `layer2d` plan draws two
canvases. The **base** holds the board gradient, the dot grid and the static prefix: the items that are not live
(`MGCanvasLayers.live`: what the motion moves, bodies with `move`, what is attached to them, vectors and edges on them,
every highlight, every moving function graph), that are drawn in full (`MGCanvasLayers.settling`: an item still
drawing on or fading is live until it ends) and whose layer rank (`MGCanvasRenderer.layer`) is lower than the lowest
rank of any live item. A static item at or above that rank is drawn in the live layer, and so are every label (base
items' labels included), the emphasis rings, the markers and the focus ring. The base canvas sits outside the
`TimelineView`, so frame-loop ticks never redraw it; SwiftUI redraws it whenever the board view is evaluated again,
which is any change of the board's state (scene revision, step, size, theme, teaching modifiers). Each canvas draws
for its own size, so both layers share one viewport. Both canvases read the current step's items from the
controller's cache, which computes them once per scene revision and step (`MGSceneController.timelineItems`,
`MGTimelineCache`), so no tick, repartition or base redraw applies the step edits again. The cache keeps the last 4
steps read (least recently used out first; at most 4 × 40 item values, items a step left unedited sharing storage
with the scene), so boards that share one controller and show different steps keep their own entries; a new scene
revision drops every entry of the old one.

The split also follows the board's own clock, which a lesson or explainer host sets (`presentationClock`), while the
transition window ends on a wall-clock wait. `MGBoardTransition.phase` says where the step and patch transitions stand
at one time on that clock: **moving** while a blend, a camera move or keyframes still change the frame (a `.bounded`
blend until its progress reaches 1, since a leaving item starts at opacity 1 and `MGCanvasLayers.settling` does not
count it; a `.spring` blend for its whole 1.2 s window; a camera move for its whole 1.0 s window), **drawing on** while
only draw-ons remain, and **settled** after that. The board draws one canvas while the phase is moving, and splits
for the phase at the time it is evaluated. The live canvas computes the phase on each tick, and when the phase it was
split for has passed (a blend or camera move has ended, or the last draw-on has), it asks for one more evaluation of
the board: one base redraw, after which the items drawn in full are in the base.

What is claimed until the Mac run: for one input the split composites to the one-canvas frame within rounding, and
the phase and draw-on decisions (`testTheSplitWaitsForBlendsAndCameraMovesOnTheBoardsClock`,
`testTheLastDrawOnEndsThePhaseOnce`) hold. What `testTheSplitBoardStaysExactAcrossTicksAndChanges` checks on a live
board in a window, at 1x and 2x, with the board's clock moved explicitly: base redraws are counted (none on ticks,
and exactly one when the first appearance's draw-on ends); while the first appearance draws on, the base holds no
item, and after it the base holds the static prefix; after a revision and after a step the board draws one canvas
until its clock has run the blend or the camera move, and then draws a base with the revised floor and the step's
camera; after each change (ticks during and after the draw-on, the revision, the step, a resized viewport, a theme
and new markers) the last base under the last live layer still matches the one-canvas frame, and every item the base
cached is drawn as it now is, with the current viewport; and taps on a base item and on a live item select through
the board's own tap handler. `testTheBoundedSplitBoardWaitsForAFadingExit` removes a base item on a `.bounded` board:
one canvas while it fades from opacity 1, then a base without it. When a split differs, the test prints where, on lines
starting `SPLIT-DIFF` (the first and the worst differing pixel, their RGBA in each image, the items covering them,
both draws' viewports) and, with `MG_STILLS_DIR` set, writes the images. Mac run #25 was the first in which the
hosted board split. Two things differed. A base drawn while the zone and the floor were drawing on kept them at that
progress through the ticks (mean difference 3.1); `MGCanvasLayers.settling` now prevents that. And the first-frame,
revision and step checks differed by 66 levels at 1x and 216 at 2x at the first window size (by the layout, a board
532 points wide and 354.67 high), while every check after the resize to 672 by 448 passed. The base frame was the only input made for another size (the reader's,
not the canvas's); each canvas now draws for its own size, and the next run shows whether that was the cause. The
run #25 revision and step checks also compared a base drawn while the blend and the camera move were still at their
start on the board's clock (the rig moves that clock only with `advance`), so they could not show a base that missed
the end of a transition; the phase rule above and the explicit clock moves in the test close that gap.
`testTheSplitBoardIsOneAccessibilityElement` checks that the split board stays one
accessibility element whose value follows a step and a rebuild with markers (accessibility properties only, no
VoiceOver run). Mac run #23 found no element under the hosting view, so the test also hosts a plain `Text` with an
accessibility label as a control: it skips, saying so, only when that control is missing (no accessibility tree at
all), and otherwise asserts the board's element count and value with no skip. The test rig sets the `.active` scene phase, which the hosted board did not read on its own in that run.

The solid renderer keeps its shadow catcher and contact shadow until the default pose's bounds or the ground option
change, so camera updates (every loop and story frame) reuse them. The key light's shadow frustum has inputs of its own
(the exploded extent, the light and its direction) and is refitted whenever those change, also when the rest bounds do
not (`SolidGroundCacheTests`).

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

Colour (**tags requested; decoded check pending**): `srgb` and `rec709` frames are drawn in sRGB, `displayP3` frames in
Display P3 (an sRGB image is converted when drawn). Every source pixel buffer is tagged with the space it was drawn in
(primaries, transfer function and colour space, `MGExportPreset.sourceAttachments`). The file asks for BT.709 primaries
and matrix with the sRGB transfer function (`srgb`, so Apple players show the video as the stills), BT.709 throughout
(`rec709`, the tags upload transcoders read), or P3-D65 primaries with the sRGB transfer function (`displayP3`). The
sRGB transfer tag is AVFoundation's documented `AVVideoTransferFunction_IEC_sRGB` where the OS has it (macOS 15,
iOS 18), else Core Video's `kCVImageBufferTransferFunction_sRGB` (macOS 10.13, iOS 11): the same "IEC_sRGB" tag.
Whether the encoder converts `rec709` frames
from the sRGB their buffers declare, and whether every file decodes to what its tags say, is what
`testColourPatchesDecodeAsTheirTagsSay` checks against tag values written out in the test (not read from the preset);
until it has run, the tags are requested, not proven. That test fails if a `rec709` file carries BT.709 tags over
sRGB samples. Mac run #23 found the samples converted, and the decoded values fit a 1.961 power curve within about one
level, not the BT.709 camera curve, so the test expects that curve. Apple documents the 1.961 exponent for macOS
playback of BT.709-tagged video; that the writer converts onto it is inferred from the run #23 samples, not documented. **Planned resolution** if it does: draw `rec709` frames in `CGColorSpace.itur_709`, so the samples match
the tags.

Alpha: H.264 and HEVC carry none. ProRes 4444 stores straight alpha (`straight`, what most editors read) or the
buffer's premultiplied colours (`premultiplied`), and the source buffers say which (`kCVImageBufferAlphaChannelModeKey`).
A 2D video exported with an alpha preset is clear where nothing is drawn: the board colour and
the letterbox are left out (label and code backdrops stay, so text stays readable on any footage). The decoded check
(`ap4h`, a clear region, a half-transparent shape, edge colours over light and dark) is pending. No preset reorders
frames, so frame k is presented at k / fps and a video of n frames lasts exactly n / fps.

## Default output changes

Four pure fixes are on by default, outside the transition switch, and change default pixels on purpose (an owner
decision for this pass). `EngineStillsTests` renders comparison stills of each; the Mac command list renders them on
this branch and, from the same file, on `5e4952e`, for a person to compare.

1. **Label placement.** 2D board labels are placed by `MGLabelLayout` (72 positions instead of 36, never over
   another label or leader, whole-point boxes with sizes rounded up) and a label pushed more than 14 points from its
   anchor gets a leader line. Crowded boards place labels differently. (Stills: `labels@1x`, `labels@2x`.)
2. **Arrow shaft shortening.** A board vector's shaft ends under its head and its head is 7...16 points and at most
   45 % of the arrow (`MGArrowGeometry`), so short and drawing-on arrows look different; a dashed shaft ends on a
   whole dash. A 2D video arrow's shaft stops just inside its head instead of at the tip. (Stills: `arrows-10@2x`,
   `arrows-30@2x`, `arrows-60@2x`, `arrows-100@2x`, `video-arrows`.)
3. **Pixel alignment.** Grid dots on whole points, 1-point table, plot-grid and label-border lines on the half-point
   grid, table cell edges on whole points. Lines and dots move by up to half a point and turn crisp. (Stills:
   `hairlines@1x`, `hairlines@2x`, `hairlines@3x`.)
4. **Cleared pooled buffer.** Every movie writer, the engine's own H.264 writer included, clears each pooled pixel
   buffer before drawing a frame. An opaque full frame looks the same; a frame with transparent pixels no longer shows
   the frame before it. (Stills: `pooled-buffer-frame1`, `pooled-buffer-frame3`.)

Designed to be pixel-identical, and not listed above: the stable draw order (`MGCanvasRenderer.ordered`, the order the
standard sort already gave), the step-items cache, and the layered split while motion plays (within rounding for one
input; the live-board check is pending, see [Layers and caches](#layers-and-caches)).

## Audit

Findings at `5e4952e` (`file:line` there), with what this branch did.

| # | Area | Finding | Where | Status |
| --- | --- | --- | --- | --- |
| 1 | 3D loop | The loop is one input turn; parts with a fractional ratio jump at the wrap (robot joint: 0.082° a frame, then 29.306° back). The glTF export bakes the same loop. | `Sources/MartyGraphics/Solid/MGSolidRenderPlan.swift:80`, `:84`; `Examples/Solid3D/Sources/MartySolidGLTF/MGSolidGLTF.swift:113` | Fixed: `MGSolidLoop`, `export-gltf --seamless` |
| 2 | Video path | Blender's centred shutter samples before key 0 and after the last key, so the first and last frames blur half; the automatic camera sweeps one way and jumps back when the video loops. | `tools/render-blender/mgrender/lookdev.py:477`, `:405` | Fixed for seamless exports (closing key, START shutter, sway) |
| 3 | Timing | Step blends, camera moves and draw-on pops use a spring that overshoots by about 12 % (a vector longer than its new length, an angle past its target) and ends on a step at 1.2 s. | `Sources/MartyGraphics/MartyGraphicsView.swift:429`, `:436`; `Sources/MartyGraphics/MGCanvasRenderer.swift:77`, `:250`; `Sources/MartyGraphics/MGTimeline.swift:135` | Opt-in: `transitionStyle(.bounded)` (`MGEasing`, `MGStepTransition`); the default board keeps the spring (owner decision) |
| 4 | Timing | Items that leave a step vanish at once; with Reduce Motion there is no transition at all and the frame loop never runs. | `Sources/MartyGraphics/MartyGraphicsView.swift:429`; `Sources/MartyGraphics/MGRenderPolicy.swift:26` | Opt-in: fade out and the Reduce Motion dissolve (`MGRenderPolicy.dissolving`) on a `.bounded` board; the default board still snaps |
| 5 | Text | Greedy placement with a least-overlap fallback and no leader lines: a pushed-away label loses its anchor; boxes sit on fractional points. | `Sources/MartyGraphics/MGLayout.swift:122`; `Sources/MartyGraphics/MGCanvasRenderer.swift:299` | Fixed: `MGLabelLayout` |
| 6 | Arrows | The head (7...14 points) is longer than a short arrow, so while an arrow draws on its head reaches behind the tail and the shaft is stroked backwards; a dashed shaft can end in a gap; 2D-video shafts are stroked to the tip, so the line end shows past the sharp head. | `Sources/MartyGraphics/MGCanvasRenderer.swift:345`, `:347`, `:355`; `Sources/MartyGraphics/MGVideoDrawing.swift:155` | Fixed: `MGArrowGeometry`, a shorter video shaft (default output change) |
| 7 | Performance | Every 2D frame re-applies every step's edits, and the whole board (gradient, dot grid, every item with its shadow layers) redraws at 60 Hz while anything moves. | `Sources/MartyGraphics/MartyGraphicsView.swift:426`, `:282`; `Sources/MartyGraphics/MGTimeline.swift:44` | Fixed: the step's items come from the controller's `MGTimelineCache` (on main); a base canvas outside the frame loop (live-board check pending) |
| 8 | Performance | `setCamera` rebuilds the ground, the contact blob and two 256 × 256 alpha images on every call, so once per loop and story frame, although they depend only on the default pose. | `Sources/MartyGraphics/Solid/MGSolidRenderer.swift:492`, `:824`, `:855` | Fixed: the ground is rebuilt only when the rest bounds change; the key light's frustum is refitted on its own inputs |
| 9 | Export | One H.264 profile (0.2 bit per pixel, 2 s key frames) tagged with the sRGB transfer function only: no destination presets, no BT.709 or P3 option, no alpha; pooled buffers are drawn over without clearing. | `Sources/MartyGraphics/MGMovieWriter.swift:27`, `:34`, `:38`, `:112` | Fixed: `MGExportPreset` (tags requested; decoded check pending), buffers cleared (default output change) |
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
| 22 | Timing | Frame pacing: the 2D loop runs at 60 Hz on the wall clock or the session's presentation clock, and only while something moves or a transition runs; 120 Hz is not requested. | `Sources/MartyGraphics/MGRenderPolicy.swift:39`; `Sources/MartyGraphics/MartyGraphicsView.swift:282` | Kept (plus the dissolve under Reduce Motion on a `.bounded` board) |
| 23 | 3D | Lighting, materials and shadows hold up: a procedural studio environment in extended linear sRGB, PBR presets, a 4096-pixel key shadow map with 24 soft samples fitted to the exploded bounds, ambient occlusion that follows the camera distance and a dithered backdrop. | `Sources/MartyGraphics/Solid/MGSolidRenderer.swift:898`, `:807`, `:839`, `:486`; `Sources/MartyGraphics/Solid/MGSolidLook.swift:182` | Kept |

## Before → after

- Turntable and mechanism loops: one input turn with a jump at the wrap → the exact period (robot joint 49/6 input
  turns, 490 frames at 30 fps) with a wrap step equal to every other step, a repeating camera and a closing frame.
- Blender video of a seamless export: half-blurred first and last frames and a one-way camera → motion blur that
  continues across the wrap and a turntable or sway that closes.
- Step changes: an overshooting spring, instant exits, nothing under Reduce Motion → unchanged by default; with
  `transitionStyle(.bounded)`, bounded quintic easing in 0.6 s, fading exits and a dissolve under Reduce Motion.
- Body and node pops: 12 % overshoot, never exactly full size → unchanged by default; with `.bounded`, a critically
  damped approach that lands on the size.
- Labels: 36 positions and overlap as a fallback → 72 positions, leader lines, no label over a leader, whole points.
- Arrowheads: reversed shafts and oversized heads on short arrows, floating dashed heads → proportional heads, a shaft
  under the head, whole dashes.
- Live 2D board while motion plays: everything at 60 Hz and every step edit re-applied per frame → the board, grid
  and static prefix in a base canvas outside the frame loop, and cached step items.
- Solid renderer: ground rebuilt per frame → built once per rest bounds, the key light refitted when its own inputs
  change.
- Video export: one H.264 setting → Shorts, X and lesson presets with BT.709, sRGB or P3 tags requested (decoded check
  pending) and ProRes 4444 straight alpha, clear where a 2D video draws nothing; pooled frames cleared.
- Hairlines: blurry 1-point lines at 1x and 3x → lines on the half-point grid, crisp at 1x, 2x and 3x.

## Verify on a Mac

From the repository root of a clean checkout of this commit on macOS 14+ with Xcode 26 (see
[Verify on Mac](VERIFY-ON-MAC.md)). No simulator and no VoiceOver run is needed: the board tests host the real view
in an `NSWindow`, and the accessibility checks read accessibility properties only.

```sh
git rev-parse HEAD && git status --porcelain
swift --version
swift build

# The whole engine suite, goldens included.
swift test

# The engine-quality suites, and the tests this fix round added.
swift test --filter 'MartyGraphicsTests.(RenderQualityTests|SolidLoopTests)'
swift test --filter 'MartyGraphicsTests.(BoardTransitionTests|BoardTransitionHostTests|ExportDecodeTests|SolidGroundCacheTests|EngineStillsTests)'

# Solid3D: the CLI goldens, the glTF exporter, the seamless export and its closing key.
swift test --package-path Examples/Solid3D
swift test --package-path Examples/Solid3D --filter 'MartySolidGLTFTests.SeamlessLoopExportTests'
swift test --package-path Examples/Solid3D --filter 'MartySolidGLTFTests.SeamlessLoopExportTests/testTheClosingKeyLooksLikeKeyZero'

# The Python tests (Blender helpers, without Blender).
python3 -m unittest discover -s tools/tests -v

# The robot-joint seamless export: 491 keys (490 loop frames and the closing key), a 490-frame period.
swift build -c release --package-path Examples/Solid3D
B=$(swift build -c release --package-path Examples/Solid3D --show-bin-path)
rm -rf /tmp/rj-seamless
$B/marty-solid export-gltf docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json /tmp/rj-seamless \
  --engine-commit "$(git rev-parse HEAD)" --seamless
python3 -c "import json; m = json.load(open('/tmp/rj-seamless/robot-joint-gearbox.manifest.json')); l = m['loop']; print(m['frameCount'], l['frames'], l['closingFrame'], l['inputTurns'])"

# Swift vectors for a later Python parity test (not committed yet): the Swift manifest's loop record, read by the
# Blender loop helpers.
mkdir -p /tmp/mg-vectors
python3 -c "import json; m = json.load(open('/tmp/rj-seamless/robot-joint-gearbox.manifest.json')); json.dump({'frameCount': m['frameCount'], 'loop': m['loop']}, open('/tmp/mg-vectors/robot-joint-seamless-loop.json', 'w'), indent=2, sort_keys=True)"
PYTHONPATH=tools/render-blender python3 -c "import json; from mgrender import loop; m = json.load(open('/tmp/mg-vectors/robot-joint-seamless-loop.json')); i = loop.loop_info(m, m['frameCount']); print(i, loop.render_range(i, m['frameCount']), loop.blur_position(i), loop.sway_frames(i))"

# Comparison stills of the default output changes: this branch, and the same file on 5e4952e.
rm -rf /tmp/mg-stills /tmp/mg-legacy
MG_STILLS_DIR=/tmp/mg-stills/new swift test --filter 'MartyGraphicsTests.EngineStillsTests'
git worktree add --detach /tmp/mg-legacy 5e4952e
cp Tests/MartyGraphicsTests/EngineStillsTests.swift /tmp/mg-legacy/Tests/MartyGraphicsTests/
(cd /tmp/mg-legacy && MG_STILLS_DIR=/tmp/mg-stills/legacy swift test --filter 'MartyGraphicsTests.EngineStillsTests')
git worktree remove --force /tmp/mg-legacy
ls /tmp/mg-stills/new /tmp/mg-stills/legacy && open /tmp/mg-stills
```

Expected: every test passes; the export prints `491 490 490 49/6`; the vector check prints
`{'seamless': True, 'frames': 490, 'closing': True, 'input_turns': '49/6'} (0, 489) START 490`. The stills folder has
the same file names under `new` and `legacy` (labels, arrows, hairlines, video arrows, pooled-buffer frames) for a
person to compare against [Default output changes](#default-output-changes); `pooled-buffer-frame1` is expected to show
red around the blue square in `legacy` and black in `new`.

`testTheClosingKeyLooksLikeKeyZero` is the closing-key check on the exported file: re-read with the independent GLB
reader, every mesh vertex at key 490 lies on a same-material vertex at key 0 and every camera node is where it was, so
key 490 shows what key 0 shows. Then, on the Linux render host of the
[Blender render path](../tools/render-blender/README.md) (after its `setup.sh`), render the copied export as a
turntable and watch the wrap; the log names the seamless loop and `render-report.json` records
`"motion_blur_position": "START"` and 490 rendered frames:
`blender -b --factory-startup -P tools/render-blender/render.py -- rj-seamless/robot-joint-gearbox.manifest.json rj-film --turntable`.

Until these have run, the claims on this page marked pending stay pending: the decoded colour and alpha checks, the
live-board layer check, the hosted transition tests, the closing-key check and every other Swift test.
