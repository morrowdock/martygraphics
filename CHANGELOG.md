# Changelog

## [Unreleased]

### Changed
- Docs: the scene v1 schema notes and the Swift parity evidence link Swift sources by file and name the symbol
  (for example `MGParser.step(_:_:)`) instead of linking line numbers, which had drifted 26 to 28 lines.
  `validate_local.py --check-files` now refuses a relative `#L<digits>` link in `docs/`.
- Hardening: tighter work and size bounds. A step or `over` edit of a `func` or `field` item now counts toward the
  six graph checks per scene (`items.expr`), because an edit checks the whole item again; one graph can take five
  edits. `tools/mg_expr.py` and `tools/scene_v1_check.py` count step edits the same way.
- Hardening: lessons take at most 2 `animate` commands per beat (and per host `apply` batch) and 24 per stream,
  set-up commands included (`lesson.animate.count`; on restore `snapshot.pending` and `snapshot.stream`). The count
  takes an `animate` before it runs, so a refused one counts too, and a `keep` stream starts from the `animate`
  commands still waiting. A beat that waits keeps its commands but no keyframe scenes; an `animate` builds its
  keyframes when its beat is presented. A snapshot of a stream with an `animate` stores the stream's count
  (`stream.animates`); `restore` holds all waiting beats to 24 together and restores at least their count.
- **Breaking:** at most 24 `animate` commands ever wait in a lesson session, across streams. A continuation (`keep`
  stream) now counts the `animate` commands still waiting from earlier streams, so an `animate` that fit the old
  per-stream limit can be refused (`lesson.animate.count`), and `restore` refuses a snapshot with more than 24
  waiting `animate` commands across streams (`snapshot.pending`). Both are deliberate. See docs/LESSONS.md.
- Hardening: `MartyGraphicsView` keeps the visible items of the shown step for each scene revision and step, so a
  drawn frame no longer applies the step edits again. The stream parser does not parse the preview again while a
  chunk completes nothing new, and runs its `steps` trial again only when the scene it checks changed. No public API
  changes.
- Hardening: the Blender render path's export check caps `frameCount` at 14,400 (the exporter's cap), the `.glb` at
  512 MiB and the manifest at 1 MiB before reading them. It keeps each accessor inside its bufferView and each
  bufferView inside buffer 0 as its `byteLength` declares it (at most the binary chunk, which may add only 0–3
  padding bytes), refuses an explicit `byteStride` that is not 4–252 and a multiple of 4, checks every index before using it (no negative index), bounds keys
  per sampler, allows one channel per node and path, and requires the hierarchy of every node, in any scene or none,
  to be a forest. Any other failure on a malformed export is a refused export with a reason (exit 1). See
  tools/render-blender/README.md.
- Docs: rewrite the README around a short description, one example image, a quick start that draws a first
  scene to a PNG, and a capability table with honest status and what is in `v0.1.0`. Add Concepts, Cookbook
  (ten scenes in `docs/cookbook`), Gallery, FAQ and For teachers pages. Correct stale release and "unreleased"
  statements in the tutorial, protocol, distribution, capabilities and quality pages.
- Docs: say that the quick start saves one frame, and state more exactly the patch revision rule, the standard and
  strict 3D checks, the outputs of `marty-solid render`, `export-gltf` and `transcript`, the section-cut caps, the
  linkage and cam limits, where the gallery images came from, and the required CI checks.
- The default grammar document lists the `func` and `field` kinds, the `alt` scene key and the closed
  expression vocabulary (`expression`); `MGTimeline.cycle` and `MGScene.animates` include moving graphs.
- Docs: the protocol, tutorial and ML explainer pages state the drawing and step conventions and link the
  authoring guide; `MGMLKit.report` takes an optional `hints:` flag whose default keeps the output unchanged.
- Engine: the 2D board keeps its spring step and patch transitions by default (spring blends and camera moves,
  spring pops, leaving items vanish, Reduce Motion snaps with no frame loop).
- Engine: while motion plays, the 2D board draws its board, grid and static prefix (static items ranked below every
  moving item) in a base canvas outside the frame loop and redraws only the live layer each tick; both read the
  current step's items from the controller's cache, which keeps the last 4 steps read (least recently used out
  first), so boards sharing one controller on different steps each compute a step's items once. Items still drawing
  on or fading stay in the live layer, and each canvas draws for its own size. The board draws one canvas until its
  blends and camera moves have ended on its own clock (the lesson's presentation clock, when set), and splits once
  more when its last draw-on ends, so the items drawn in full move into the base. The live-board check of the split is
  pending Mac verification.
- Engine: the solid renderer builds its ground and contact shadow once per rest bounds instead of once per frame,
  and refits the key light's shadow frustum whenever the exploded extent or the light changes.
- Engine, intentional default output changes (pure fixes, on by default; comparison stills and the list in
  docs/ENGINE.md, "Default output changes"):
  - label placement: 2D board labels are placed by `MGLabelLayout` (72 positions, whole-point boxes, a leader line
    for a label pushed away from its anchor), so crowded boards place labels differently;
  - arrow shaft shortening: a board vector's head keeps its proportions on short and drawing-on arrows and its shaft
    ends under the head, a dashed shaft ends on a whole dash, and a 2D video arrow's shaft stops inside its head;
  - pixel alignment: grid dots, 1-point table, plot-grid and label-border lines and table cell edges sit on the
    pixel grid at 1x, 2x and 3x;
  - cleared pooled buffer: every movie writer, the engine's own H.264 writer included, clears each pooled pixel
    buffer before drawing a frame.
- Docs: clarify that a coding agent wrote the turbofan JSON directly in the documented
  format, consistently with the site, showcase and provenance receipt.
- Docs: describe the opt-in ML explainer kit and the Blender video tool (16:9, 1:1 and 9:16,
  turntable, transparent 9:16 frames) in the README; tighten wording in the portability
  proposal, capabilities table and public-sync notes.
- CI: the hosted `macos-engine-rest` shard now also runs the `Examples/LessonDemo` tests on macOS.
- **Dry packing without blinded-key access (2026-11-13, A-19).** Use only the
  reviewed bicycle key with dedicated `DRY-BICYCLE` ID in dry mode, preserve
  the rubric hash gate, and record that registered question files were not read.
  Primary packing behavior remains unchanged. Synthetic CLI regression/golden
  tests cover the boundary; operational acceptance remains pending.
- **Registered G2 model correction (2026-11-13, A-18).** Select `gemini-4-argon`
  with exact-id HIGH throughout the Gemini adapter and grading runner. Keep the
  named preview fallback disabled without recorded owner approval. Restrict
  `model-access-check --model` and record the tested ID; explicit human quota
  confirmation and the one-attempt limit remain. Refresh stale readiness records.
  No model call was made; RUN-LOCK stays DRAFT.
- **`studio` is the default look, and live views draw its backdrop (pixels only).** `marty-solid render`,
  `MGSolidRenderer` and the explainer view now use `studio` unless told otherwise; pass `--look classic` (or
  `look: .classic`) for the renderer as it was. The explainer's live 3D pane draws the look's backdrop as the scene
  background (`MGSolidRenderer.liveBackdropSize`), so the app matches the exported stills and videos. The four
  render goldens change one line (`"look" : "studio"`). Check reports and `snapshot.json` are unchanged. The
  published images under `docs/assets` were rendered with `classic` and are regenerated separately.
- **The `studio` and `paper` looks draw modern type, plates and bands (pixels only).** No black title or caption
  bars: text sits on the look's own backdrop in the look's ink, with measured contrast of at least 4.5:1. Label
  plates are rounded with a hairline edge and a tier bar; leaders have a casing and a ringed anchor; every drawn
  metric is a multiple of the label font size. The model's cut at a band fades into the backdrop. Band sizes, the
  safe window, framing, font sizes, line breaks, label boxes and every JSON output are unchanged; `classic` draws as
  before. Turning marks on machined metals are a little fainter.
- **The `studio` and `paper` looks finish surfaces (pixels only).** Parts reflect a procedural product studio with
  soft-edged boxes, so metals show gradients; plastics get a glossy clear coat and a calibrated colour of the same
  hue; machined metals get fine per-fragment turning marks; ambient occlusion no longer draws faint rings on curved
  faces; the radial streaks on flat gear faces are gone in these looks. `classic` is unchanged, and so are the
  exported material parameters, the rig in `snapshot.json` and every check report.
  [docs/SOLID-3D.md](docs/SOLID-3D.md#looks-and-quality) has the before and after.
- **Faster CI that does not block merges.** The hosted macOS tests now run in four shards on four `macos-26`
  runners at the same time (about 13 minutes instead of about 43). Every split is a `--filter` shard plus a `--skip`
  shard with the same pattern, so no test is dropped; a filter shard that runs no test fails. No test changed, tests
  in one shard still run one at a time, and there are still no caches. `macos` (a short job that passes only when
  all shards pass) still runs on every pull request and push, but it is no longer a required merge check: the
  required checks are `hygiene` and `maintainer/local-validation`. A red `macos` after a merge is fixed or reverted
  at once.
- Note in the source why lesson and explainer reasons keep their own unknown-key rule.

### Added
- Add a draft JSON Schema and a dependency-free Python preflight for core v1 scenes. Swift remains the authority.
- Portability step 1, inventory and tests only (no file moves, no API change, no support claim
  for Windows, Linux or browsers): `docs/PORTABILITY-MAP.md` maps the imports of each source file,
  the public types that name platform types, and the package edges that block the candidate core
  files. It also suggests seams. `tools/portability_map.py` generates the tables and a tool test
  checks that they are current. `docs/fixtures/semantics/` adds 71 original synthetic fixtures with
  expected-result files. They cover parser acceptance and refusal, number formatting, template
  items and steps, a patch sequence with a rolled-back update, stream finalization and timeline
  samples. `tools/semantic_fixtures.py` checks what Python can reproduce. It uses the draft
  preflight `tools/scene_v1_check.py` and its schema.
  Every Swift-facing expectation stays `pending-mac`.
- Add the 2D `func` kind (pending Mac verification): the engine samples y = f(x) from a closed,
  bounded expression grammar (`MGExpression`; no `NSExpression` or other host evaluator), draws gaps
  and poles without joining them, shades an interval, marks a point with engine-computed coordinates,
  takes `a`, `b`, `c` parameters and moves seamlessly with `period` and `t`. Graphs that cannot be
  drawn faithfully are refused (`func.detail`, `func.breaks`, `func.empty`, `func.loop`). A gap at an
  interval midpoint between two finite samples splits the curve too, so no line or shade crosses it.
- Add the 2D `field` kind (pending Mac verification): engine-evaluated arrows on a grid of up to
  16 × 12 cells, with proportional, unit and slope (direction-field) styles and the largest magnitude
  written under the frame. At most six `func` and `field` items per scene (`items.expr`).
- Add text alternatives (pending Mac verification): `alt` on scenes and steps, read by VoiceOver after
  the narration in `MartyGraphicsView`; `MGDescribe` writes a structural description of the visible
  board, which `describesBoard()` reads when no `alt` is authored. Scenes without `alt` read as before.
- Add audio graphs for `plot`, `func` and `bars` (pending Mac verification; VoiceOver not run on a device):
  while such an item is visible, `MartyGraphicsView` gives the board an `AXChartDescriptor` built by
  `MGAudioGraph` from the engine's values (axis titles and ranges from the scene, the `func` samples the
  engine drew, one series per drawn piece, bar labels, values and unit) with an `MGDescribe` summary. It
  charts only what the board draws: `MGCanvasRenderer` and `MGAudioGraph` share the checks (`MGGraph`). At
  most 290 points per item (`MGAudioGraph.maxPoints`). The chart is the motion's first frame, which the board
  shows with Reduce Motion on. Boards without these items read exactly as before. No wire change.
- Add `graphs` and `wave` fixtures, golden expression and graph cases, and `tools/mg_expr.py`, an offline
  mirror of the new rules for preflight tools, tested in the `hygiene` job.
- Add learner sliders (pending Mac verification), an opt-in `sliders` scene key: up to 3 sliders, each
  setting `a`, `b` or `c` on every `func` that sets it, over a range within ±1,000 in at most 100 equal
  steps. The parser checks the default against each driven graph and both ends of the range through the
  item rules, with one reason per failure (`slider.step`, `slider.unbound`, `slider.b.max.func.detail`,
  …) and a one-line fix for each in `MGRepairHint`. `MGSliderState` re-parses the driven graphs for
  every position, so every sample and readout number comes from the engine; a refused position keeps the
  board and says why. `MartyGraphicsView` shows native sliders under the board with VoiceOver label,
  value, hint and an adjustable action, Dynamic Type text and engine readouts; the board's audio graph is
  built from the items at the slider values. A slider move ends any step, scene or keyframe transition in
  flight, so the board and its audio graph show the same items; while motion plays, a split board stays
  split, and during a step it splits as soon as the camera move ends. Values are written with the slider's own
  precision, or with
  significant digits where six places would not name the grid stop (a nonzero value never reads as `0`);
  a grid whose stops are too close to tell apart is refused (`slider.grid`). The engine gets exactly the
  shown value: at every stop, the ends and the default included, it is the number the label reads as; a grid
  whose end or stop label does not read back exactly is refused (`slider.grid`), and a default that is not
  exactly a stop's value is refused (`slider.default`).
  Lessons and explainer boards
  drop scene sliders, as they drop scene steps. Scenes without `sliders` are unchanged. The grammar
  document lists the key (`sceneKeys`) and the slider shape (`sliders`); the draft schema, the preflight
  and `tools/mg_expr.py` know the key, and `docs/fixtures/v1/sliders.cases.json` holds shared cases.
- Docs: a researched, ranked vNext roadmap (docs/proposals/ROADMAP-VNEXT.md).
- The draft scene v1 schema and `tools/scene_v1_check.py` accept `func`, `field` and the scene and step `alt`
  keys. For literal scenes, the preflight runs the `tools/mg_expr.py` rules on each graph and field item.
- Add an authoring guide for the 2D renderer (`docs/AUTHORING.md`): the drawing conventions the keys alone do
  not show (vector angles, incline geometry, plot, bars, array and table anchors, step timing and `show`), an
  optional review checklist, worked examples and a common-mistakes table.
- Add a one-line fix hint for every scene and ML refusal reason: `MGRepairHint.text(for:)`, `MGMLReason.hint` and
  `marty-scene-validate --hints` (also with `--ml-kit --strict`). Reasons and the default output are unchanged.
  The Swift changes are pending Mac verification.
- Add `tools/scene_lint.py`, an authoring lint for 2D scenes: warnings for displayed numbers that round away,
  clipped plot points, items outside the world (rotated boxes and every shown step included), focus on a
  highlight and negative bars; review cues for step 0 edits, ground hatching and `move`. It reports what it does
  not check (template and 3D scenes, text width, vectors anchored with `on`).
- Add a dev authoring eval (`evals/dev-authoring`): 40 original requests with machine-checkable specs, a grader,
  Python mirrors of the validators, baseline and improved runs by one author that also designed the specs, and
  checked-in inventories for the author-independent counts. It does not measure an accuracy change; an
  independent author run is pending.
- Seamless loops for turntable and mechanism exports: `MGSolidLoop` finds the exact period of an assembly's
  motion from exact joint rates and the rotational symmetry measured on its meshes, checks it on every moving part
  and plans a loop with no jump at the wrap (the robot-joint gearbox: 49/6 input turns instead of one).
  `marty-solid export-gltf --seamless` writes that loop with a closing frame and a manifest `loop` object, and the
  Blender render path renders it with a forward shutter and a closing turntable or camera sway.
- Opt-in bounded transitions for the 2D board: `MartyGraphicsView.transitionStyle(.bounded)` (`MGTransitionStyle`)
  eases step and patch changes over 0.6 s with no value past either step (`MGStepTransition`), fades leaving items
  out, lands body and node pops on their size and, with Reduce Motion, dissolves instead of snapping.
- Export presets for YouTube Shorts (1080×1920), X (1920×1080) and lessons (1920×1200) with BT.709, sRGB or
  Display P3 colour tags (tags requested; decoded check pending) and ProRes 4444 straight-alpha masters:
  `MGExportPreset`, `MGMovieWriter(url:preset:)` and `MGVideoExportOptions(preset:)`. Preset writers tag each source
  pixel buffer with the space it was drawn in and how its alpha is stored, and a 2D video exported with an alpha
  preset is clear where nothing is drawn (decoded check pending). If the decoded check finds sRGB samples under BT.709
  tags, `rec709` frames will be drawn in BT.709 (`CGColorSpace.itur_709`).
- Leader lines for 2D board labels: `MGLabelLayout` places labels deterministically and connects a label that had
  to move away from its anchor back to it.
- Add checked ML explainer boards for PCA and illustrative meaning maps, real PNG patch values,
  seeded or greedy token generation, temperature sweeps, and simplified patch attention.
  Add a camera-right landscape composition and optional sequential highlights for the vision pipeline.
- Add five strict-checked Solid3D examples with paired CLI goldens: a compound
  spur reduction, direct and idler drive comparison, ring-driven planetary,
  reciprocating plunger, and direct-drive quadcopter arm.
- Render checked Blender exports as landscape, square, and portrait video with an
  optional 360° camera orbit and a transparent PNG or ProRes 4444 compositing master.
  The variant wrapper uses `--no-burn-in`. Provenance stays in the MP4 metadata,
  `PROVENANCE.txt`, and `render-report.json`.
- Add a driven parallelogram four-bar schematic, an eccentric cam and follower,
  and a drone motor with propeller. Authored rotation ratios give exact motion
  for this parallelogram. The engine has no four-bar solver and does not check
  loop closure.
- Add the opt-in `MartyGraphicsMLKit` library with checked vision-to-language, next-token probability
  and agent-loop items. Export silent MP4 or transparent PNG frames in landscape, square and portrait.
  The probability board keeps stage labels steady as bars animate and identifies filtered-out candidates.
- Experimental, opt-in `layer2d` programmatic video: checked native 2D keyframes,
  shared library H.264 MP4 and bounded GIF export, captions and SRT sidecars.
  Legacy scene parsing remains unchanged unless `programmaticVideo: true` is supplied.

### Fixed
- Two test expressions (the seamless-loop vertex transform and the audio-graph worst-case sampler) are split into typed steps. On the hosted macOS runners (Xcode 26.6), the compiler timed out type-checking them, so the hosted macOS jobs had failed since #105.
- For items built in code, the renderer keeps its rounding and truncation and skips only a conversion whose result cannot be represented as an `Int`. For a vector angle this affects the fan-out grouping only. Spring coils are drawn only in the parser's 3–24 range, and a plot is labelled only when it has an origin point.
- Item blends and the transition spring treat a negative elapsed time as the start of the transition, so a blend never extrapolates past its starting frame.
- Bound patch diagnostics, validate video text and full video and ML identifiers, and check template text and motion before preview. Template travel, visual duration and period are limited to 0.3–10 seconds, with holds up to 10 seconds.
- Keep scene diagnostics short and reserve line feeds for text items and narration.
- Bound stream buffers and preview validation work, guarantee forward progress, and restore the
  committed scene when restarting a stream. Require a minimum plot range span.
- The movie writer clears each pooled pixel buffer before it draws a frame, so a frame with transparent pixels no
  longer shows the frame before it (a default output change, listed above).
- The shaft of a 2D video arrow no longer shows past the arrowhead's tip (a default output change, listed above).
- Use map distance for hand-placed ML points and draw vector links only for positive cosine matches.
  Remove the chosen-token caption from temperature sweeps and refuse color metadata in pixel-value PNGs.
- Reduce programmatic MP4 export stalls under encoder buffer pressure with an
  eight-buffer pool and shorter, monotonic readiness and allocation timeouts.
- Format programmatic-video zero tick labels with a floating-point argument,
  avoiding format-type warnings and normalizing negative zero to `0`.
- Include measured code text and line highlights in shared preview/preflight bounds,
  so accepted layouts cannot draw code into the reserved caption band.
- Hide mutable movie encoder internals behind append/finish/cancel operations;
  the shared low-level writer requires an explicit experimental SPI import.
- `tools/portability_map.py` skips files under hidden folders, so the generated Swift that SwiftPM leaves in a built
  package's `.build` no longer makes `--check` fail on a Mac. A validate_local test fixture no longer uses two
  folders that differ only by case, which a case-insensitive file system merges.
- `tools/write_native_receipt.py` replaces `NEW_EXPORT_DIR` with the new showcase export folder only where it is the
  argument right after `--export` in `Examples/Showcase`, and refuses to run any command when the token appears in
  another argument or another package. The receipt format is unchanged: `commands` still records the token.
- A stale wait no longer closes the 2D board's transition window (pending Mac verification). The task that waits
  for the window keeps the token of the change it was started for. A task that wakes after a later step or patch,
  before SwiftUI cancels it, no longer closes the window that change opened, which ended its frame loop early.

### Earlier entries (not sorted by type)

- **Dry packing without blinded-key access (2026-11-13, A-19).** Use only the
  reviewed bicycle key with dedicated `DRY-BICYCLE` ID in dry mode, preserve
  the rubric hash gate, and record that registered question files were not read.
  Primary packing behavior remains unchanged. Synthetic CLI regression/golden
  tests cover the boundary; operational acceptance remains pending.

- **Registered G2 model correction (2026-11-13, A-18).** Select `gemini-4-argon`
  with exact-id HIGH throughout the Gemini adapter and grading runner. Keep the
  named preview fallback disabled without recorded owner approval. Restrict
  `model-access-check --model` and record the tested ID; explicit human quota
  confirmation and the one-attempt limit remain. Refresh stale readiness records.
  No model call was made; RUN-LOCK stays DRAFT.

- **Proposed G2 Gemini CLI adapter.** Record the owner-approved change from agy
  to Gemini CLI 0.68.0. Add isolated OAuth transport, durable exact-session
  recovery, synthetic failure tests and quota-free native library checks.
  Argon is unlisted; account access unverified. The Pro preview fallback remains
  proposed and requires owner approval. Real settings-loader checks, explicit
  empty remap contexts, model-specific HIGH overrides and a final tool-registry
  dispatch guard correct the initial isolation claims. A separate human-run
  model-access check records one minimal request; auth-check stays quota-free.
  No model call was made; RUN-LOCK stays DRAFT.
- **Proposed live benchmark adapters.** Add isolated Codex CLI transport,
  durable receipts, exact-session fix-up, fake CLI tests and a quota-free dry
  self-test command. Antigravity remains UNVERIFIED and fails closed; the full
  live runner is not ready. Replace test reads of registered keys with
  synthetic metadata. No model call or registered benchmark run was made.
- **Benchmark harness: scoring and analysis (draft for review).** `benchmark/mechanisms-v1/harness/` adds the
  primary scoring and grade-merge code that the protocol requires before run 1, and the whole analysis plan:
  - the per-check merge of the two graders;
  - the mechanism score (N/A when no check is judged), coverage, errors, clarity and defects;
  - failed-run scores with E_fail(q) (undefined without a graded output);
  - ungraded outputs, listed and left out;
  - M(q, a) and the exact sign test with the 15-of-20 boundary, all in exact fractions;
  - every exploratory analysis and the agreement statistics, with their bootstrap intervals.

  One validator (`rubric_form.py`) defines a valid grader reply for both the grading runner and the scorer. That
  covers the evidence rules, conventional-configuration N/A, reply identity from the published mapping, and the
  section 6 attempts. A dated `RECORD.json` of every grading attempt and the run timing decides whether a result may
  carry the registered verdict. `agreement.py` is tested against published values.

  NumPy is required at the version RUN-LOCK.json pins (2.5.4); everything else is the standard library. The tests
  use synthetic data only. `RUN-LOCK.json` is a draft with the harness hashes. `AMENDMENTS.md` records the decided
  open points with honest labels, and `harness/OPEN-QUESTIONS.md` records the options that were considered. No
  question, key fact, check, prompt, rubric or protocol text changed, and nothing outside `benchmark/` changed
  except this file and `FILES.json`.
- **glTF export for offline renders (the one exception to the engine feature freeze).** `marty-solid export-gltf
  FILE.json NEW_DIR --engine-commit SHA` and `marty-turbofan --export-gltf NEW_DIR --engine-commit SHA` write the
  scene and its loop motion as glTF 2.0 binary (`.glb`): one node per part in the part hierarchy, meshes in metres
  (+Y up), simple PBR materials, the loop camera and still cameras, the studio's directional lights, and one
  translation and rotation key per frame for every moving node (default 30 fps). The sidecar manifest has the format
  of the Blender render path, `martygraphics.render-export/1`. The exporter runs only after the strict check passes,
  lives outside the engine library (library `MartySolidGLTF` in `Examples/Solid3D`) and changes no engine output. A
  test re-reads the gearbox export and matches every node to the engine's transform within 1e-5 m and 1e-5 rad; two
  exports are byte-identical. See [docs/GLTF-EXPORT.md](docs/GLTF-EXPORT.md).
- **Blender render path (`tools/render-blender/`).** Owner decision 2026-11-11: verify in MartyGraphics, render in
  Blender. `setup.sh` installs the official Blender 5.2.4 LTS Linux build in user space and checks its published
  SHA-256; `render.py` renders a `martygraphics.render-export/1` export (`.glb` + manifest) in Cycles with HDRI
  lighting, a studio or shadow-catcher backdrop, material presets, an export or auto-orbit camera, depth of field,
  motion blur, AgX, adaptive sampling and denoising, to a PNG sequence, a fast-start H.264 MP4 and a poster. It refuses
  an export whose `.glb` SHA-256, fps or frame count differs from the manifest, proves that imported and look-dev
  motion equal the glTF evaluation at every frame, labels every output with its provenance, and has an optional,
  read-only busy guard (lock file, process pattern or command; off unless configured) that keeps it from starting or
  continuing while the host is busy. `selftest.sh` checks the whole path on a 2:1 gear pair without an export.
- **v0.2 plan (docs only).** [docs/V0.2-PLAN.md](docs/V0.2-PLAN.md) ranks the engine changes that real authoring
  runs recorded as gaps (drone and aviation explainers, Part 107 Nights 1 and 2): a label size key, a transcript
  export, a feet display unit, declared phrase names, a pin closure check and three smaller items. Each item is its
  own pull request after the owner's go.
- **Looks and quality levels for the built-in renderer (pixels only).** `marty-solid render --look
  classic|studio|paper` and `MGSolidRenderer(document:look:)` choose how a solid is presented: `studio` is a graphite
  studio sweep with a pool of light under the subject, `paper` a near-white one; both make shadows land on a floor,
  keep the outline of dark parts and the form of white parts, and use a dithered backdrop that does not band.
  `classic` (the default when introduced) is the renderer as it was. `MGSolidQuality` (`interactive`, `balanced`,
  `still`) sets the cost of a frame through `MGStudioOptions(quality:)`; `still` equals `MGStudioOptions()`. The explainer view takes
  both (`MGExplainerController.solidLook`, `solidQuality`, default `balanced`: 16 shadow samples instead of 24). No
  check report or snapshot changes for any look (tested). The render `manifest.json` gains one member, `look` (the
  look the images were drawn with), so the four render goldens gain the line `"look" : "classic"` and nothing else. Design:
  [docs/VISUAL-STYLE.md](docs/VISUAL-STYLE.md); details: [docs/SOLID-3D.md](docs/SOLID-3D.md#looks-and-quality).
- **Transcript export (v0.2 G2).** `marty-solid transcript FILE.json [--strict]` and `MGTranscript` print every
  caption, every shown label, arrow and dimension text, and every board table, per beat, as plain reflowable text for
  screen readers, large text and a static equivalent ([docs/EXPLAINER.md](docs/EXPLAINER.md#transcript)). The format is
  the one the Part 107 course transcripts were written in by hand (`morrowdock-explainer-transcript` v1), so the
  engine now makes them. The document is checked first; a refused document prints its check report. Read-only: no
  check, report or render output changes. Golden transcripts for the five drone explainers, the jet-suit lesson and a
  board-only explainer. Closes the transcript workaround of a recorded course gap (no label size key).
- **Drone and aviation explainers (docs only, no engine change).** `docs/assets/drone-aviation` adds five hand-built
  explainers made with the engine as it is: quadcopter steering, payload position and centre of gravity, a brushless
  outrunner motor, a three-axis camera gimbal and a landing gear over-centre lock. Each folder holds the document, the exact brief, every attempt
  (39 in all: 14 refused, 2 of them deliberate negative controls), the strict check output, a story video and stills.
  `FACTS.md` lists every claim with a source and what the engine checked. Two independent fact checks (Sol and
  Gemini) found no wrong claim; all 16 fixes are applied to the captions, labels and `FACTS.md` (words only), with a
  new render of the story videos and of the stills whose words changed.
  `GAPS.md` lists what the frozen engine could not show (the helicopter swashplate topic was dropped), with exact
  refusal texts. `docs/SHOWCASE.md` has a new section. Golden check files for the eleven new JSON files.

### Fixed
- Native receipt reuse in `tools/validate_local.py` takes the covered packages from the repository (`.` and every
  other folder with a `Package.swift`, plus `tools/render-blender`) and the inputs their tests read from outside
  them (such as `Examples/Explainers`, `docs/fixtures` and `docs/assets`). The old fixed list named a nonexistent
  `Examples/UnitCircle` and missed Solid3D, Turbofan, Explainers, LessonDemo, KeySwitch3D, PathTrace and
  render-blender. A reused native receipt (`--native-receipt`) must name each present package with exit 0, and any
  changed, added or removed native file fails reuse. See [docs/LOCAL-VALIDATION.md](docs/LOCAL-VALIDATION.md).
- Native receipt reuse covers what it missed: every file of a folder that a Swift literal names, Markdown too; any
  top-level path a literal names, so `CHANGELOG.md` (a root test reads it) is now an input and editing it needs a new
  native receipt; custom target paths, resources and local dependencies that a package manifest names outside the
  package; and the tracked targets of covered symlinks. Swift sources, manifests and links are read from the two
  pinned commits, not the working tree, and renames (case-only ones too) count. A covered symlink or a manifest
  dependency that leaves the repository or names nothing refuses reuse. A receipt must name exactly the present
  packages, each with exit 0; `missing`, `unexpected` and `failed` entries are reported separately, and the refusal
  says how to make a new receipt. `.build` folders and the `vendor` and `third_party` roots are not packages. The new
  `tools/write_native_receipt.py` runs the Mac package commands with the same package discovery and writes the
  receipt outside a clean checkout.
- Native receipt reuse also reads `Package@swift-*.swift` manifests and the target of a `.swift` symlink, and refuses
  reuse when a submodule sits in a covered path or package. `tools/render-blender/selftest.sh` checks that
  `blender --version` is the pinned 5.2.4, even with `BLENDER` or `BLENDER_VERSION` set, and exits 127 without a
  Blender executable and 3 for another version.
- A symlinked package manifest is read in the link's package folder, and its target file is a native input. The
  native commands of every package, now including the showcase `--verify` and `--export` runs, are one table in
  `tools/validate_local.py` that the receipt writer runs and docs/VERIFY-ON-MAC.md quotes, checked by a test. The
  Blender self-test accepts only a "Blender 5.2.4" or "Blender 5.2.4 LTS" release line and exits 3 when
  `blender --version` fails.
- Native receipts are version 2: each package records the argv lists it ran next to its exit code, with a
  `commands_sha256` over them, and reuse is refused (as `commands`) when they differ from the current
  `PACKAGE_COMMANDS`, so an old build-only Showcase receipt no longer passes. Version 1 receipts are refused with a
  prompt to re-run the writer. Commands are argv lists throughout, so a package path with a space stays one argument.
- Changelog: there is one `[Unreleased]` section. The entries of a second, unbracketed `Unreleased` section moved
  into it under standard categories, with their text unchanged.
- Changelog correction: the "Looks and quality levels" entry under Added says `classic` (the default). Since "`studio`
  is the default look", the default is `studio`; pass `--look classic` (or `look: .classic`) for the classic look.
- Changelog correction: the v0.1.0 notes say hosted CI (`hygiene`, `macos`) gates every merge. That held at the
  release. Since "Faster CI that does not block merges", only the `hygiene` check and the
  `maintainer/local-validation` status are required; `macos` runs on every pull request but does not block a merge.
- Bound patch diagnostics, validate video text and full video and ML identifiers, and check template text and motion before preview. Template travel, visual duration and period are limited to 0.3–10 seconds, with holds up to 10 seconds.
- Keep scene diagnostics short and reserve line feeds for text items and narration.
- Bound stream buffers and preview validation work, guarantee forward progress, and restore the
  committed scene when restarting a stream. Require a minimum plot range span.
- Use map distance for hand-placed ML points and draw vector links only for positive cosine matches.
  Remove the chosen-token caption from temperature sweeps and refuse color metadata in pixel-value PNGs.
- Reduce programmatic MP4 export stalls under encoder buffer pressure with an
  eight-buffer pool and shorter, monotonic readiness and allocation timeouts.
- Format programmatic-video zero tick labels with a floating-point argument,
  avoiding format-type warnings and normalizing negative zero to `0`.
- Include measured code text and line highlights in shared preview/preflight bounds,
  so accepted layouts cannot draw code into the reserved caption band.
- Hide mutable movie encoder internals behind append/finish/cancel operations;
  the shared low-level writer requires an explicit experimental SPI import.
- **Story and loop videos carry colour tags.** The MP4 files are tagged sRGB with BT.709 primaries and matrix (they
  were untagged). A player that assumed a BT.709 transfer function and converted for the display showed the middle
  tones several levels off the stills; on the `studio` backdrop that was visible. The frames written are the same.
- **A part's own light still glows in `studio` and `paper`.** Their bloom starts above what a lit surface reaches
  (`MGSolidLook.bloomThreshold`), so emitters keep their coloured glow and white parts get no halo.

## v0.1.0 — 2026-11-11

The first tagged release. **Early preview:** the API and the JSON formats can still change. Swift 6, macOS 14+ and
iOS 17+, no external packages. Every change in full: [docs/HISTORY.md](docs/HISTORY.md).

### What it does

- **Kinematically checked 3D mechanism explainers.** A Foundation-only solid kernel (extrude, revolve, tube, involute
  spur and ring gears, blades and blade rows, capped partial revolves) and assemblies with revolute and prismatic
  joints and gear meshes, solved from one input. A closed-key JSON format (assembly v1 and v2) refuses a wrong
  document with one stable reason and the part, for example `constraint.gearMesh.phase` on `ring1`
  ([reason catalog](docs/REASONS.md)). v2 adds section cuts, see-through parts, labels, arrows and measured
  dimensions, reusable components and a facts table: a caption takes its numbers from the solved values.
- **Explainer documents.** One document drives a 2D board, a 3D solid or both on one beat timeline, with one legend
  that counts only what the learner was shown ([docs/EXPLAINER.md](docs/EXPLAINER.md)).
- **A strict check made for AI authors.** `--strict` refuses labels and arrows that a step does not show, gravity and
  dimension claims that motion can break (with proven bounds), and text numbers that the engine did not compute.
  Reports give exact, validated repairs.
- **`marty-solid`** (`Examples/Solid3D`): `check` prints the JSON report; `render` writes stills, a loop, a story
  video and a manifest with digests.
- **2D scenes and lessons.** Validated v1 scenes for SwiftUI diagrams, plots, arrays and trees, with templates,
  patches and streaming; beat-by-beat lessons with saved state ([docs/LESSONS.md](docs/LESSONS.md)).
- **Also:** `MartyGraphicsPathTracer` (Metal path tracing), 3D inspection hooks, `marty-scene-validate` and the
  `Examples/`. At release, both `hygiene` and `macos` were required.

### Shown with real output

- A schematic two-spool turbofan cutaway from 38 lines of example JSON, written directly in the format, not from a
  prompt ([docs/assets/turbofan](docs/assets/turbofan)).
- A robot-joint gearbox from a prompt: Claude Haiku 5.5 wrote it, the engine refused try 1
  (`constraint.gearMesh.phase`: 20 + 56 does not divide by 3) and accepted try 2
  ([docs/assets/from-a-prompt/robot-joint](docs/assets/from-a-prompt/robot-joint)).
- An AI-written jet-suit lesson (Claude Opus 5.5 through Marty), shown unedited beside an independent fact check that
  found 1 wrong sentence and 12 corrections ([docs/SHOWCASE.md](docs/SHOWCASE.md)).

### Next: a blind benchmark

[benchmark/mechanisms-v1](benchmark/mechanisms-v1/README.md) pre-registers a comparison of MartyGraphics through Marty
against the same model writing three.js directly, on 20 mechanism questions. It is design only and not run; there is
no result yet.

### Limits

- Not checked: the meaning of words, strength, load, wear, friction, air or gas flow, forces other than the gravity
  direction, and collisions. Gear contact is checked in 2D at sampled angles. The only linkage is the slider-crank;
  there are no helical or bevel gears, belts or cams ([docs/SOLID-3D.md](docs/SOLID-3D.md#limits-1)).
- "Solved" in a legend means a ratio computed from the model's own joints and drives, not a fact about the real object.
- Reliability is not good enough yet. In a 50-question development test, Claude Haiku 5.5 got all 40 in-scope
  questions accepted within three repairs, but only 29 of 40 were fully correct in mechanics.
- The renderers need Apple frameworks. Windows, Linux and browser builds are not supported.
- Parses, reports, cameras, layout and snapshots are byte-identical across processes; 3D pixels are not (at most
  5.02 % of the pixels in a still differed, measured 2026-11-10).
- The remote Swift Package Manager install is checked after tagging ([docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)).

### How it was made

AI agents (mainly Claude Opus 5.5) wrote the code and the docs under the direction of Collin Craig. After the first
import commits, changes went through pull requests with recorded local checks and independent reviews by other AI
models. The fact checks are AI model checks with web access, not an engineer's review. The
showcase runs were picked after grading from the runs that passed, and the 50-question set was used to
tune the engine, so its results are not held-out evidence.
