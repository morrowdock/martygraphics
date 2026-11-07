# Changelog

## Unreleased

- Fix the `two_pointers` template stopping after 8 steps, so a 12-value walk never reached its pair. It and `bst` now use the template step limit (`MGLimits.templateSteps`, 48) instead of the wire limit (`MGLimits.steps`, 8). Output of walks that fit in 8 steps is unchanged.
- Show the beat-by-beat rotation lesson in the README and `docs/SHOWCASE.md`: a 640×400 loop, beat stills and a
  learner-slider still in `docs/assets/lessons/` with a capture receipt. Add `lesson-demo --capture <new directory>
  [WIDTHxHEIGHT]` to `Examples/LessonDemo`: it plans one run headless on the demo's default pacing (beat states, the
  start scene and engine keyframes of each `animate`, a scripted learner's slider ticks), shows each planned frame on
  the live demo view offscreen, and writes the frames, `frames.json` and a GIF whose delays are the planned times
  (ImageIO, no external tools). The plan and the GIF writer are example code (`LessonDemoKit/Capture.swift`) with tests.
- Add `MGLessonController.restore(_:)` to adopt a saved lesson state (`MGLessonSession.snapshot()`) on a live
  controller. The snapshot is validated first; a refused snapshot changes nothing but `lastIssue`. On success the board
  shows the restored state with no blend, keyframes or draw-on (new `MGSceneController.show(_:transition:drawsOn:)` and
  `MGAdoption.plan(…, drawsOn:)`), also for a beat that the restore makes due at once; selection is cleared, timing
  marks are reset with no first-visible time, a restore never starts playback, and the remaining settle time of an
  interrupted animation is dropped. Add `MGLessonController.feed(_: Data)` to replay `unfinishedInput`.
- Compatibility change for every lesson host: bound lesson sessions so that every snapshot a session makes restores.
  Each path that changes a session (stream statements and `load`, host `apply`, learner values, `restore`) keeps each
  snapshot part inside its bound and refuses a change that would pass it, with the state unchanged:
  - Beats received but not shown yet may take at most 96 KiB of snapshot JSON across all streams
    (`lesson.queue.bytes`). A `.speech` or paused host that streams faster than it shows must apply backpressure.
  - The id history holds at most 1024 ids, removed ids included, until a new scene (`lesson.ids.count`).
  - A filled line is at most 2 KiB (`stmt.say.bytes`), checked when its beat closes and when it is presented.
  - One bound control is at most 1 KiB (`control.bytes`).

  `MGLessonSession.restore` enforces the same bounds:
  - title rule: `snapshot.title`
  - caption size: `snapshot.caption`
  - id history keys and count: `snapshot.kinds`, `snapshot.introduced`
  - queue: `snapshot.pending`
  - controls: `control.bytes`

  Before it reads any field, restore runs one bounded walk as defence in depth. Over the derived 291,570-byte cap is
  `snapshot.bytes`, a NaN or infinite number is `snapshot.number`, and deeper than the derived 2,056 levels is
  `snapshot.depth` (the depth fits the deepest legal raw-template `params`). Line timing on restore follows the
  restoring pacing (`.estimate` keeps or re-estimates an open line, `.speech` waits, `.immediate` holds no line), so a
  paused snapshot restored under another pacing no longer leaves a stale line timer.
- Add the 2D item kinds `table` (a grid of up to 8 × 6 short cells with an optional
  header row and marked cells) and `region` (a filled closed polygon of 3 to 64
  points), and the text style `code` (monospaced, left-aligned, keeps leading spaces,
  allows `<` and `>` but not markup tags). They are additive: every scene that parsed
  before parses to the same result. All three are refused in 3D. New reasons:
  `table.cells`, `table.cell`, `table.marked`, `region.pts`, `3d.text.code`. The core pack gains a
  synthetic `cells` fixture and `docs/fixtures/v1/table-region-code.scene.json`.
- Add raw templates, `MGTemplate(name:summary:paramsDoc:sample:compile:)`, whose
  `params` object is free-form JSON of at most 4 KiB (`MGLimits.rawParamsBytes`,
  `template.params.bytes`); the template validates it. `MGParams.raw` carries it,
  `isRaw`, `paramsDoc` and `sample` describe it, and `MGGrammar.document()` lists a
  `rawParams` shape only for raw templates. Template `make` may now throw: a
  `template.<suffix>` reason that follows the `reject` suffix rule is kept, any
  other thrown reason or error is `template.build`.
- Add `MGParamSpec.listDefault` for number lists (absent key uses the default; pack
  validation refuses a default that does not fit, `template.<p>.default` when parsed
  without registration). `MGGrammar.document()` lists `listDefaults` only for templates
  that declare one. `MGParamSpec.doc` now says `numbers` instead of `ints` for a
  non-integer list and shows a list default.
- Packs may carry follow-up patches (`MGFixtures.PatchDemo`) and fail-safe cases;
  `MGPacks.validate` applies every patch to its fixture and requires every fail-safe
  case to be refused (`MGPackError.patchInvalid`, `.invalidAccepted`). The core pack
  ships six new patches and 24 new fail-safe cases.
- Make these public for hosts: `MGParser.scene(data:|object:|json:extraTemplates:)`,
  `MGScene.applying(_:extraTemplates:)`, `MGTemplate.validate(_:)` and
  `compile(_:is3D:)` (validate, then build), `MGPacks.builtIn`, and
  `MGPatch(ops:baseRevision:)`. `applying` now checks every patch with the `parse`
  rules (operation count, finite numbers, operation keys, byte bound), so a patch built
  in code fails safe instead of trapping on a missing `item`.
- Refuse NaN and infinities in `MGJSON` values built in code before encoding them
  (the system encoder raised an uncatchable exception): `scene.number`,
  `patch.number`, `template.params.number`, and for lessons `lesson.number` (document,
  `load` statement, `apply` command; before, such a statement became an empty line and
  was skipped) and `snapshot.number`. New `MGJSON.isEncodable` and
  `canonicalByteCount` (`Int.max` when not encodable); every byte bound, including the
  solid assembly, component and lesson document bounds, now uses it, so an unencodable value never
  counts as 0 bytes.
- Source-compatibility change: `MGKind` gains `table` and `region`, and `MGPackError`
  gains `patchInvalid` and `invalidAccepted`. External exhaustive switches over these
  enums must be updated; `MGKind.allCases` and the grammar `kinds` list grow by two.
- Patch blending no longer interpolates a table's row and column counts.
- Add beat-by-beat lessons (phase 1). A lesson document or a streamed statement lane (one JSON object per statement)
  drives a Foundation-only `MGLessonSession`: beats with spoken lines, the existing patch ops plus `animate`, `bind`,
  `unbind` and `check`, a persistent `MGLessonState` with stable ids, engine-filled narration and labels, refusals
  with stable reasons and locations that leave the state unchanged, `.speech` / `.estimate` / `.immediate` pacing with
  ordered timing events, `snapshot()` / `restore`, and separate time-to-first-visible and time-to-complete marks. Add
  the opt-in `MGGeometryPack` (`rotate2d`: every rotated coordinate computed in Swift), `MGSceneDiff`, `MGTween`
  keyframes and the SwiftUI `MGLessonController` / `MartyGraphicsLessonView`, where a slider sends the same `params`
  command as a scripted beat. `MGSceneController` gains opt-in transitions (`.direct` for a finger: no blend and no
  draw-on replay; `.keyframes` for `animate`: true rotations instead of the chord-cutting point blend); existing calls
  keep the blend. Add `Examples/LessonDemo` (rotation lesson with `--verify`, `--timing`, `--render`, `--preview`) and
  `docs/LESSONS.md`. Scene and patch formats stay at v1; the default grammar document is unchanged.
  After independent review: a refused `say` no longer closes or presents the open beat; a command that would make an
  accepted `check` false is refused, and checks are evaluated again on the final and on the presented state; the
  stream budget counts every received byte and at most 256 statements, then stops with one refusal; reasons are
  bounded single tokens; learner refusals have a fixed order; each `animate` keeps its own timed keyframe segment
  (cuts, not chords, between them); control labels may not hold placeholders; snapshots keep the projection of queued
  beats; a second `load` always reaches the board; pause holds an in-flight animation and its settle time; template
  walkthroughs are flattened in lessons; leading-dot decimals and exponents count as decimal literals; one header per stream.
  After a second review: refused input after a finished lesson no longer reopens playback; a beat refused at due time
  leaves the projection on the shown state; set-up animations settle before `lessonComplete`; `2.e3` counts as a
  decimal literal; `MGTween.keyframes` refuses a bad `maxStep` (`animate.step`); a refused controller `load` keeps the
  current lesson; lesson-owned unknown keys become author segments; `unfinishedInput` lets a host replay a partial
  statement after `restore`.
- Add a maintainer-dispatched hosted `macos` CI job (standard `macos-26` runner) that builds and tests the root package, examples and SceneValidator; GPU tests skip themselves on hosted VMs.
- Add reusable solid components. A component is a closed-key JSON definition with
  numeric parameters (`default`, `min`, `max`, `integer`), parts and constraints whose
  numbers may be small expressions (`param`, `add`, `sub`, `mul`, `div`, `min`, `max`,
  `neg`, `pi`, `sin`, `cos`; deterministic and bounded), named checks, and anchors. An
  assembly uses one with `{"id": "stage", "use": "planetaryStage", "with": {…}}`; it
  expands before compiling into parts with ids such as `stage.sun`, so every existing
  check, limit and the mesh budget apply to the expanded parts. `set` edits inner
  parts, `at` / `rot` / `parent` place the instance, components can nest three levels,
  and patches reach inner parts. `MGSolidLibrary.builtIn` ships `spurPair`,
  `planetaryStage`, `sliderCrank`, `propeller`, `housingBase`, `shaftWithBearing` and
  `fanStage`; hosts register more at runtime (validated and compiled on registration)
  and `catalog()` lists them compactly. `marty-solid` gains `components`,
  `component check FILE.json [--with NAME=VALUE]` and `--component FILE`. The
  planetary example drops from 53 lines (3,721 bytes) to 12 lines (927 bytes) and the
  slider-crank from 21 lines to 8. Reasons now keep `.` in author names
  (`ref.unknown.stage.ghost`). Part ids, `repeat` copy ids, instance ids and anchors
  share one namespace (a collision is refused, never resolved silently); references may
  name single copies (`p.blade1`); resolved ids, repeat suffix included, are at most
  64 characters. A dotted `parent` that names no part now reports `ref.unknown.<id>`
  instead of `part.parent`, also in documents without components.
- Add `pitch` to the `blade` primitive: the section angle is `pitch + twist × t`. Document
  the angle convention (chord along +Y, leading edge toward −Y, positive turns +Y toward
  +Z). The propeller example and the `propeller` component now turn about −Z (leading
  edge first) with pitch −40° and twist +28°, so the blades are steep at the hub and
  flatter at the tip, as the example text says. Before, the root was flat and the tip
  steep, and the blades moved trailing edge first.
- `marty-solid render` describes a one-line (minified) source by its size, for example
  "812 bytes on one line", instead of "1 lines". `Examples/Solid3D` gains CLI tests that
  run `marty-solid` in fresh processes.
  (`ref.unknown.stage.ghost`).
- Lead the README and the showcase with the first AI-written result: a two-stage planetary
  gearbox written by Claude Haiku 5.5 from one prompt, refused once with an exact reason and
  fixed by the model. Both attempts, the renders and a run receipt are in
  `docs/assets/from-a-prompt/robot-joint`.
- Say in the README and the showcase that the loops are GIF previews (at most 256 colours,
  10 to 12 frames per second, 480 to 640 pixels wide), and link the 1280-wide, 24 to 30 frames
  per second source videos.
- Add turbomachinery primitives to the solid engine: `bladeRow` (a NACA-style airfoil with
  stagger, twist and signed camber, wrapped on cylinders and repeated around the axis) and
  capped partial revolves (`revolvedProfile` `sweep` and `start`) for cutaway casings, with
  stable refusal reasons and exact `meshEstimate` counts for the mesh budget. Add the
  `titanium`, `nickelAlloy`, `composite` and `ceramic` material presets. Add
  `Examples/Turbofan`: a schematic two-spool, high-bypass turbofan from 38 lines of JSON (LP
  spool at N1, HP spool at N2 = 3 × N1, eight teaching steps), `--verify` checks for closed
  meshes, coaxial spools, the authored speed ratio and a lower bound on swept clearance, real-time stills and a
  seamless 12-second loop, and `MartySolidRT`, which maps an `MGSolidSnapshot` to an
  `MGRTScene` so the same model is path traced. Render receipt in `docs/assets/turbofan`.
  The README now leads with the turbofan loop and shows the path-traced gearbox as a
  640×360 loop GIF.
- Name missing keys in solid-format refusals (`part.drive.crankSlider.missing.radius,rod`
  instead of `….missing`). In a recorded prompt-to-3D trial a model wrote `crankRadius`
  and `rodLength`, received only `missing` three times and never found the right keys.
- Document the solid format's text limits (title 80, part name 60, step text 240) and
  that `at` / `rot` go inside each shape entry, and add worked example models for crank
  drives (`slider-crank.json`) and repeated blades (`propeller.json`), kept valid by a
  test. Found in the first prompt-to-3D trial, where most repairs were text-length
  refusals and models skipped drives the docs described without an example.
- Add `marty-solid`, a command in `Examples/Solid3D` that checks or renders any solid
  assembly JSON file. `check` prints a JSON report with the exact refusal reason or the
  solved ratios and engine checks. `render` writes stills, captioned step images, a loop
  GIF, a snapshot for other renderers and a manifest with digests and render time.
- Add a solid 3D engine to `MartyGraphics`: a Foundation-only geometry kernel (closed
  meshes; extrude, revolve, tube, involute spur and internal ring gears, twisted and tapered
  blades), assemblies with revolute and prismatic joints and gear-mesh constraints solved
  from one input, a closed-key JSON assembly format with exact refusal reasons, and a
  SceneKit studio renderer with physically based presets, soft shadows, section planes and
  part highlights. `MGSolidSnapshot` exports a posed frame as plain arrays. Add
  `Examples/Solid3D`: a planetary gear set rendered from 53 lines of JSON and a slider-crank
  cutaway, with a render receipt in `docs/assets/solid`. Schematic teaching models.
- Add `MartyGraphicsPathTracer`, a separate library that path traces triangle meshes with
  Metal ray tracing in a compute kernel (runs on Apple silicon without ray-tracing hardware):
  next-event estimation with MIS, anisotropic GGX metals, plastic, clear coat, rough and
  smooth glass, a procedural importance-sampled studio environment, area lights, thin-lens
  depth of field, an edge-aware à-trous denoiser and an ACES tonemap. The core
  `MartyGraphics` library does not depend on it. Add `Examples/PathTrace`, a procedurally
  generated 7:1 gearbox rendered as stills, an exploded view, a code side-by-side and a
  seamless 10-second loop, with a render receipt in `docs/assets/pathtrace`.
- Add opt-in 3D inspection hooks. `inspects3D(_:)` with `MG3DInspection` (`.selection`,
  `.emphasis`, `.dimming`) lets the existing `selection`, `markers` and `emphasis`
  modifiers act on a 3D board; as in 2D, highlights, axes and ground lines are never
  selected, and a highlight follows its target's look. `preserves3DCamera(resetKey:)`
  keeps orbit and zoom across updates of the same scene and re-frames on a reset key,
  scene camera, world size or scene identity change. Without these modifiers 3D boards
  behave exactly as before. 3D picks the nearest hit of the earliest probe, whereas 2D
  picks the smallest footprint; `.dimming` has no 2D counterpart.
- Add `Examples/KeySwitch3D`, a schematic key-switch teaching model (not physically
  validated) with a parts list, press/explode/actuation sliders and reset. Click-select,
  drag-orbit and reset were checked on screen on macOS.
- Add a shortest-path walkthrough to the native showcase. The showcase registers
  the opt-in graph pack, the README and gallery show the new capture, and every
  native capture is re-exported at one recorded commit. The capture receipt now
  also pins the SHA-256 of each scene, tool and engine source file. The README
  gains a short, labelled plans section.
- Source-compatibility change: the new `MGPackError.badParamSpec` case
  requires external exhaustive switches to be updated. `MGTemplate` also gains
  an optional `reject:` initializer argument.
- Add record-list template parameters (`MGParamSpec.records`), checked at
  pack registration, with specific cross-field rejection reasons and record
  shapes in the grammar for templates that use them; plus an opt-in
  `MGGraphPack` with a locally computed `shortest_path` (Dijkstra) walkthrough
  with semantic edge ids. Narration notes equal-cost relaxations into unsettled
  nodes, and the summary counts tied shortest simple paths. New bounds apply to
  the new shape only; no existing limit or wire format changes. Known limits:
  edge status is shown by colour only, dense automatic layouts are not
  visually accepted, and visual, accessibility and frame-cost acceptance
  have not been done.
- Refuse numeric array cells whose displayed text is longer than the
  6-character cell limit (for example `-123456` or `999999.5`) with
  `array.val` at first parse. Such scenes used to parse and then fail every
  later step edit or patch of that array. Values are never altered.
- Fix three engine round-trip bugs. Default node radius and array cell size
  are now capped to the maximum their own keys accept, so a defaulted item's
  wire form re-parses when the world's larger side is under 3 (node) or 4
  (array) units. In those tiny worlds such items draw smaller than before (at
  a larger side of 2, the default radius is 1/3 instead of 0.5 and the cell
  0.5 instead of 1); other worlds are unchanged. A highlight whose anchor
  chain leads to a hidden item is now hidden too, not only one level deep.
  Streaming previews are refused for any complete scene version other than 1,
  matching `finish()`.
- Add synthetic regression suites for parser limits, streaming previews,
  timeline visibility, patch atomicity and controller rollback.
- Add `marty-scene-validate` in `tools/SceneValidator`, a macOS-only command that
  checks named scene JSON files with the engine parser and reports text or JSON
  results with documented exit codes. It does not render scenes or judge visual
  quality. Native-source receipt reuse now also requires fresh evidence when the
  validator package, sources or tests change.
- Add a guarded post-approval remote-SPM smoke command and offline guard tests,
  with exact tag/commit/pin checks and private evidence. Remote-install acceptance
  remains pending a real reviewed release; add DocC/SPI preparation gates only.
- Expand the v1 Markdown protocol/API reference with developer error reasons,
  limits/platform tables and synthetic JSON fixtures; document reviewed release,
  remote-install and package-discovery gates without inventing a release tag.
- Clarify local preview package setup and live-scene revision handling; add a
  complete title-change example and a first-edit guide for showcase scenes.
- Add a local native showcase for original algorithm, system-diagram, plot,
  synthetic-data and motion examples, with interactive preview and frame export.
- Add a guided API tutorial, public/app capability matrix, quality evidence plan,
  portable-core/browser architecture proposal and reviewed public-sync process.
- Improve README navigation and direct links to example source.
- Include original native PNG/GIF captures with pinned source and measured stored timing.
- Check DCO against explicit PR base/head SHAs, including contributor merges;
  provide reproducible local validation receipts and manual-only hosted checks.

New example execution, accepted capture assets and review are recorded at the
candidate revision; an unreleased entry is not a new published release or tag.
