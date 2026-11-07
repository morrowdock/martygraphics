# Changelog

## Unreleased

- Add explainer documents (`"kind": "explainer"`, version 1): one document with a 2D board (a v1 scene), a 3D solid
  (an assembly v2) or both, driven by ONE beat timeline, with one id namespace and one legend (docs/EXPLAINER.md,
  `Examples/Explainers`).
  - `MGExplainer` (document: closed keys, limits, notes, the flattened statement stream), `MGExplainerSession` (the
    statement lane: header, keep, board, solid, say, op, check, view, highlight, end; one lesson session for the 2D
    state and pacing; per-beat 3D views compiled as solid steps so cuts are budgeted; highlights of 2D items, table
    rows and cells (`t.r2`, `t.r1c0`) and 3D parts; 2D and 3D checks; refusal coupling; events; TE1–TE6 timing;
    `describe`; `snapshot` / `restore`), `MGExplainerReport` (ONE check report for both views),
    `MGExplainerLegend` / `MGExplainerClaim` / `MGTier`, and `MGExplainerController` with `MartyGraphicsExplainerView`
    (SwiftUI: two panes, caption, legend, signposts).
  - One namespace: 2D item and control ids, 3D part, copy, `repeat` base, instance and anchor ids; collisions are
    refused (`explainer.id.duplicate.<id>`), checked on final names in canonical order. Rule N1 across both views:
    every number character in author text comes from a placeholder (`{name}` = 2D value, `{part.fact}` = 3D fact) or
    the 2D item carries a note (`basis`: "Data as given"; `unchecked`: "Not checked"). Legend groups `Solved ·
    Schematic · Given · Not checked`; a 3D-only explainer has its assembly's own legend text.
  - `marty-solid check` and `render` dispatch on the top-level `kind`: `explainer` takes the new path (`--strict`
    also refuses `notes.unused.<id>`; `render --snapshots` writes `snapshot-beat-<n>.json`); a lesson document gives
    the new `kind.unsupported`; everything else keeps the assembly path, byte-identical (the golden test passes
    unchanged). The tool now reads up to 128 KiB before it dispatches; a file over 128 KiB whose text holds
    `"explainer"` is `explainer.bytes`, any other is `assembly.bytes` as before.
  - The reason catalog (`MGSolidReasons`, `docs/REASONS.md`) gains the format `explainer` and every explainer
    reason; `tier.key`, `check.fact.<name>`, `check.failed.<name>`, `text.sign.<name>`, the `text.modifier` reasons
    and `report.engine` also list `explainer`. `MGSolidReasons.explainerStrictPrefixes` names what the explainer's
    strict check refuses. The catalog test now scans `Sources/MartyGraphics/Explainer` too.
  - Additive public API: `MGRenderInput.tableRows` / `tableCells` (row and cell emphasis, empty by default),
    `MGTemplateBuild.builtValues` and `MGScene.builtValues` (template values marked as author data; empty for every
    built-in template), `MGExplainerBoard.input`. No signature changed.
  - Compatibility: plain scenes, patches, lessons and assemblies are unchanged. The new parser environment, the
    lesson hooks (boardless mode, external fill, N1 instead of the D3 decimal rule, close-time refusals, `forward`)
    and the scanner's statement cap are internal and off by default; tests B1–B7 and the existing suites pin this.
  - Review fixes (PR #32): restore trusts nothing in a snapshot as proof (it replays the script from the board with
    the explainer's rules, checks every scene and queued command the lesson holds, derives captions again, in beat
    order then statement order); after a learner or host change the caption shows live values and a 2D check that
    no longer holds leaves the claims (`notCurrent`); 2D item claims come from the scenes, so refused beats and
    notes on template-built items are counted correctly; the SwiftUI host plays a beat's spin over time, freezes it
    on pause, applies the beat's camera and orbit, plays the board's transitions, shows bound sliders and the legend
    notes, and draws 3D highlights with the new `.strong` emphasis (`MGSolidRenderer.emphasis`, default `.subtle`
    unchanged); the renamed view and 3D check reasons (`view.camera`, `view.section.parts`, `check.unknown.<keys>`,
    …) are in the catalog; `marty-solid snapshot check` restores an explainer snapshot;
    `MartyGraphicsView.tableEmphasis(rows:cells:)`.
  - Re-check fixes (PR #32): while the board still animates to a beat's state, the caption shows its 2D numbers as
    "…" and the beat's 2D checks are pending (`boardSettled`, `motionRemaining`, `pendingClaims`); restore refuses a
    saved control that no checked `bind` made (`snapshot.controls`) and a saved check that is not a check, so a
    restored legend equals a fresh run's.
  - Third-check fixes (PR #32): a beat's `lineDue` with a 2D engine number waits until the board shows its state
    (speech is learner-visible); `finishNow` and `.immediate` pacing give the board the end state as a direct change
    in the same step; restore applies the board rules to every held scene (a forged heading is
    `explainer.board.title`) and keeps no inner lesson title.
  - The board view draws its transitions on `MGSceneController.presentationClock` when set (default nil: the wall
    clock, as before). `MGLessonController` and `MGExplainerController` set their session's monotonic clock, so a
    wall-clock jump cannot show an earlier frame while the session says the board has settled.
  - 3D annotations (PR 3a, merged before this PR) inside explainers: annotation ids join the one namespace,
    annotation claims and the solid's legend notes join the one legend, beat views take `annotate`
    (`view.annotate…`), the check report carries the assembly's `annotations`, and hosts draw annotations only
    through `checkedAnnotations` (`MGSolidRenderer(document:)`, `show(document:view:)`, the frame overlay). A
    caption, the title or board text may show a `dim.<id>` fact only when it holds at every pose of its views
    (`text.pose.beat.<n>`, `text.pose.title`, `text.pose.board`).
  - Not in this PR: 3D annotations (labels, arrows, dimensions; open-vocabulary PR 3a, still in review). Their ids
    join the namespace, the claims and the report at marked seams once it merges; until then `annotations` in a
    solid is refused with `assembly.unknown.annotations`. The card's 3D example shows its facts in captions instead
    of an arrow and a dimension.
- Docs: showcase 3D annotations with the hand-built winch example (two stills, its strict check output and a capture receipt in `docs/assets/annotations`, a SHOWCASE section and a README paragraph). No code change.
- Add 3D annotations to assembly v2 (open vocabulary 3a): a top-level `annotations` object with `labels`, `arrows`
  and `dimensions`, and a step key `annotate`. Both are refused in v1 documents with the usual reasons
  (`assembly.unknown.annotations`, `step.unknown.annotate`). Anchors name a part (its origin, an `offset` in its frame
  or its mesh `centre`) or a world point; a `repeat` base with copies or an instance id is `anchor.ambiguous.<id>`.
  Annotation ids join the document's one namespace. Text fills placeholders and follows rule N1
  (`text.number.label.<id>`, `text.number.arrow.<id>`, `text.number.dimension.<id>`, or `unchecked`); `abs` is refused.
  Arrows mean `force`, `flow`, `motion` or `pointer`. The engine computes every motion direction: a turn arrow's sense
  from the part's turn (a stated `sense` that is wrong is `arrow.sense.<id>`), a line arrow's direction from the
  anchor's velocity, looking ahead at a dead centre (a stated `expect` more than 30° off is `arrow.expect.<id>`); a
  gravity force must point within 10° of −Z (`arrow.gravity.<id>`). A dimension measures a distance (optionally along
  one axis) or an angle between anchors at the default input, or its range over one input turn with
  `"over": "input"`; its value is the Solved fact `dim.<id>` and is never typed. Limits: 32 labels, 32 arrows,
  16 dimensions, 12 visible at once (`annotations.visible`, `step.annotate.count`). Arrow and dimension pieces join
  the mesh budget with exact counts before any mesh is built. Annotation claims (kind `annotation`) join the legend,
  which gains `notes` ("Arrow lengths are not to scale"). New warnings `annotation.unused.<id>` (refused by the
  strict profile) and `annotation.cut.<id>`. One deterministic placement function (`MGAnnotationLayout.place`,
  through `MGSolidAnnotations.frame`) places text boxes at 24 candidates by hard rules and a score, keeps places
  between frames, and moves text it cannot place into a numbered callout list; nothing is dropped. An occlusion ray
  test (2,000,000 triangle tests per frame) gives hollow dots and dashed leaders. `MGSolidRenderer` (loaded with
  `init(document:)` or `setDocument(_:)`, shown with `show(document:view:)`) draws arrows and dimension lines in SceneKit without rebuilding geometry while the pose changes;
  `MGSolidOverlayView` (SwiftUI) and `MGSolidOverlay.draw` (CoreGraphics) draw labels, leaders, callouts and the
  legend from the same records. Snapshot `/2` gains optional `annotations` (arrow and dimension triangles after every
  part triangle, labels, placements) and `highlight`; a `/2` export without them keeps its bytes, and a `/1` file with
  them is refused. `marty-solid check` reports `annotations` and `placements` (only for annotated documents) and
  `marty-solid render` draws the overlay on every still and GIF frame. New v2 worked example `annotated-winch.json`
  (a hand winch with labels, two turn arrows, a gravity force arrow, a checked motion arrow and a measured centre
  distance). See [docs/SOLID-3D.md](docs/SOLID-3D.md#annotations-v2).
  - Every displayed annotation claim holds at every pose its view can show (a step's `spin` range at its explode
    value, played backwards for a negative `spin`; the plain view's default pose), decided by exact rules with no
    sampling: dimensions, and `dim.<id>` facts in any shown text, must be constant in the view; gravity arrows must
    not turn; motion line arrows must not ride a turning joint in a moving step; `over` ranges come from the joint
    closed forms (`annotation.pose.<id>`, `text.pose.step.<n>`, `text.pose.title`, `dimension.over.motion.<id>`).
    Motion arrows, turn arrows, `expect` and dimensions in moving steps need a linear motion chain (constant-rate input,
    follow and gear drives); a crank chain is `annotation.motion.nonlinear.<id>`. A turn arrow shows the sign of its
    composed world rate (`arrow.turn.steady.<id>` when there is none). One gate,
    `MGSolidDocument.checkedAnnotations(_:params:)`, decides what a view may show at a pose; a view is bound to the
    fingerprint of the document it came from (`checkedFingerprint`) and to its step's playback sense; frames,
    SceneKit and snapshots all use it. `marty-solid render` draws annotations on `hero.png` and the step stills only.
  - Source-compatibility change: `MGSolidClaim.Kind` gains `annotation`; an exhaustive `switch` over it outside
    the package needs the new case.
  - Source-compatibility change: a compiled document is read-only to hosts. Every stored property of
    `MGSolidDocument`, `MGSolidStep`, `MGSolidGear`, `MGSolidFact`, `MGSolidStepSection` and `MGSolidView` now has
    an internal setter (`public internal(set) var`); change a document through `MGSolidParser.applying`, which
    recompiles and re-checks it, and get views from `view(step:)`. `MGSolidView.parts` and `section` were settable
    before (#22); a host now changes a part's appearance through the document (`opacity`, `ghost`, `section`). A document with annotations keeps `params.input` within 10,000 turns (`annotations.input`).
  - `MGSolidView` gains `annotations`, `motionSense`, `step` and `fingerprint` (all read-only); `MGSolidLegend` gains `notes`;
    `MGAnnotationFrame.refusal` (`unchecked`, `viewSize`) says why a frame laid out nothing.
- Add the solid check report as a library API, an engine identity, patch checks, a reason catalog, per-part tiers
  and a guarded snapshot decoder (Foundation only).
  - `MGSolidReport` builds the `marty-solid check` report in the library: `check(data:library:profile:engine:)`,
    `check(data:patch:…)`, `make(_:profile:source:engine:)`, `refused(…)`, `Checks` (closed meshes, step cuts, the
    gear tooth sweep) and `text` (the exact bytes the tool prints). `MGSolidSource` gives the `file` facts with a
    Foundation SHA-256. The tool now calls the library. A golden test pins the output: for every shipped example
    and every JSON file under `docs/assets`, with and without `--strict`, the output without the added fields is
    byte-identical to the previous release.
  - New report fields: `engine`; `partTiers` (each part's motion: `own` with its tier and source, `idle`, `rides`
    with the moving ancestor, or `static`); `motionTiers` (one entry per motion claim).
  - `MGEngine` (`name`, `version` = `"unreleased"`, `reportFormat` = 1, `identity`). `marty-solid version` prints
    it with `executableSHA256`, the SHA-256 of the running binary; `check`, `render`, `component check` and the
    render manifest carry the same `engine` object. The engine does not report a git commit.
  - `marty-solid check BASE.json --patch PATCH.json` and `MGSolidParser.applying(data:to:profile:)`: patch text is
    refused over 64 KiB (`patch.bytes`, new), when it is not UTF-8 JSON text (`patch.json`, new for solid
    patches) or deeper than 64 levels (`patch.depth`); the report adds `patch` (`fields`, `changed`, `applied`,
    `refusedAt`).
  - `MGSolidReasons` and `marty-solid reasons`: one table of every stable Solid 3D reason (pattern, meaning,
    formats, warning or refusal) with typed slots, `matches(_:)`, `lookup(_:)`, and `docs/REASONS.md`. A test
    scans the Solid sources and the tool and fails when a reason-shaped string is not in the catalog; another
    resolves sample reasons of every pattern (author names with `.missing.` or `.unknown.` included) to that
    pattern. Three strings that the engine already gives for two causes are documented (`component.unknown.<keys>`,
    `component.expr.div`, `step.ghost`).
  - Report entry points refuse an unusable host `engine` value first (`report.engine`: non-finite, deeper than 8
    levels or larger than 4,096 bytes), and `MGSolidReport.text` measures a value before it converts or encodes it
    (`report.encoding`), so no recursive step sees a deep value; tested on a 512 KiB thread.
  - `MGSolidRenderPlan`: the render sequence as data (hero, exploded, one still per step, the 120 loop frames,
    captions, footer, snapshot choice and manifest). `marty-solid render` draws it; its output is unchanged apart
    from `engine` in the printed JSON and the manifest.
  - `MGSolidSnapshot.decode(data:)` runs the #28 guards before `JSONDecoder` (new reasons `solidSnapshot.bytes`
    over 256 MiB, `solidSnapshot.json`, `solidSnapshot.depth`, `solidSnapshot.number` for a literal over 64
    characters or one that is not finite, `solidSnapshot.invalid`); the tests decode through it, also on a 512 KiB
    thread. `JSONDecoder` on `MGSolidSnapshot` still works and skips the guards.
- Docs: a showcase section, "Cutaways and honest numbers", for the hand-built `idler-gearbox.json` example (capped section cut, ghost step, engine-filled caption with its truth tier), with three stills and a capture receipt in `docs/assets/cutaway/`. No code change.
- Compatibility change: JSON nests at most 64 levels (arrays and objects on one path) at every public entry point
  (`MGLimits.depth`). Before, nested input could overflow the stack and crash the process: about 100,000 levels on a
  macOS main thread, and a few hundred nested objects on a 512 KiB thread stack (iOS secondary threads) or the 1 MiB
  iOS main thread. The encoder, the system parser, `MGJSON(any:)`, `==`, hashing and freeing all recurse once per
  level. Each entry point now counts the nesting first, without recursion: on JSON text before the system parser, on
  a value built in code before anything reads, compares or encodes it.
  - Newly refused: a scene, patch or raw template `params` that nests deeper than 64 levels (`scene.depth`,
    `patch.depth`, `template.params.depth`). This affects a raw template whose free-form `params` nest more than
    about 60 levels, which was accepted before. The shipped templates, packs, fixtures, models and built-in components
    nest at most 12.
  - Newly refused in Solid 3D: an assembly (`assembly.depth`), a patch (`patch.depth`) or a component definition
    (`component.nesting`) deeper than 64 levels.
  - JSON `Data` must be UTF-8. Every `Data` entry point (`MGParser.scene(data:)`, `MGPatch.parse(data:)`,
    `MGLesson.parse(data:)`, lesson stream statements, `MGSolidParser.document(data:)`, `MGSolidLibrary.validate` and
    `register`) newly refuses bytes that are not valid UTF-8 or that hold a raw NUL byte, with its `json` reason
    (`json`, `patch.json`, `lesson.json`, `stmt.json`), before the system parser. Before, UTF-16 and UTF-32 text was
    accepted; the nesting counter cannot read it, so a deep UTF-16 document could still crash a 512 KiB thread.
  - `MGJSON(any:)` returns nil for nesting deeper than 64; `canonicalData` and `canonicalByteCount` never encode a
    deeper value (`Int.max`).
  - For a value built in code the order is `.number`, `.depth`, then the byte bound. A value built in code that is
    over 64 levels and was refused before for its size or shape now reports `.depth`.
- Compatibility change for lesson hosts: a statement or command that nests deeper than 59 levels
  (`MGLessonLimits.statementDepth`) is newly refused with the new reason `lesson.depth`: stream statements (counted on
  the text), `load`, host `apply` and `MGLessonController.apply`. A lesson document deeper than 63 levels is refused
  by `MGLesson.parse`. Before, a stream statement could nest up to 512 levels and a host `apply` up to the patch size.
  `MGLessonLimits.snapshotDepth` is now 64 (was 2,056 in the unreleased entry below); `restore` also refuses a scene
  source deeper than 61 levels, the deepest a live session makes (`snapshot.depth`). So every snapshot a session makes,
  also a restored one, restores and reads back from JSON text.
- Compatibility change: `MGLessonSession.restore` applies the live header's decimal-literal rule to the title, so a
  snapshot whose title holds a decimal literal (`1.5`, `.5`, `2e3`) is refused with `snapshot.title`.
- Document in `docs/LESSONS.md` that a beat refused at close for the queue budget (`lesson.queue.bytes`) retracts the
  commands and checks already accepted for it.
- Add capped section cuts, see-through parts and part light to assembly v2
  (open-vocabulary phase 1, second part). A v2 step can now cut parts open:
  `"section": {"normal": […], "offset": 0, "parts": ["casing"]}` removes the points with
  `normal · p > offset` from the listed parts only. The cut is a true section: the core
  (`MGSolidSection`, Foundation only) cuts each closed shell, chains the open edges into
  loops and fills them with cap faces through `MGTriangulator`, so a cut part stays a
  closed, outward mesh with solid cut walls. A pre-pass counts every cut exactly before
  any cut triangle is built, and cuts count toward the mesh budget (all distinct cuts
  of a document read at most 400,000 part triangles, and the cap work, including the
  hole-to-outer search, is budgeted too, both `section.budget`; measured benchmarks on an
  Apple M1 check in 0.03–1.1 s, and a 120-tooth ring allows 13 distinct planes). A listed part that
  the plane misses or removes completely is refused (`section.miss.<id>`,
  `section.empty.<id>`). A step's `ghost` list shows parts at opacity 0.2. Parts take
  `opacity` (0.1–1, `part.opacity`) and `emissive` (`{"role", "intensity" 0–4}`,
  `part.emissive`). These keys are refused in v1 documents. `MGSolidDocument.view(step:)`
  gives what a step shows. `MGSolidRenderer.show(_:)` swaps in the capped geometry and
  applies opacity and emission (SceneKit). The renderer's older fragment-discard
  section option stays for compatibility. New snapshot format v2
  (`MGSolidSnapshot.make(_:step:params:)`) adds per-part `opacity`, cap triangle ranges,
  material `emission` and the step `section`. The decoder accepts `/1` and `/2`. A `/1`
  snapshot keeps its exact bytes, and a `/1` file with v2 fields is refused.
  Each hole goes to the smallest outer loop that contains it, and loops that touch at a
  vertex are split or joined there. Every built cut is checked (closed, outward, caps
  without overlap) and refused as `section.open.<id>` if it fails. Caps are triangulated by
  an ear clipper that tests reflex vertices through a grid, or the zipper strip.
  `marty-solid check` reports each step section (sound, cap triangles, cap loops) and
  counts cut triangles in `triangles`, and `marty-solid render` shows each step's cuts and
  ghosts. `render` now writes snapshot `/2` for every v2 document (v1 documents keep `/1`). New v2 worked example
  `idler-gearbox.json` (16, 23 and 28 teeth on shafts along Y, a casing cut open).
- Add assembly v2 and an honesty layer to the solid engine (open-vocabulary phase 1,
  first part). `"v": 2` is a strict superset of v1; v1 documents keep their exact
  meaning, and a v1 document with a v2 key is refused with the usual
  `….unknown.<key>` reason. The engine now keeps a facts table
  (`MGSolidDocument.facts`: tooth counts, modules, joint speeds per input turn relative to
  the parent and in the world frame, prismatic travel over one input turn, crank radius
  and rod length, `repeat` counts and `<instance>.ratio`; component anchors resolve, so
  `stage.output.speed` works). In v2 the title and step text fill `{name}` placeholders
  with closed modifiers (`abs` only with a strict-inequality check that proves the sign,
  `inv`, `pct`, `deg`, `frac`, so `{stage.output.speed|frac}` prints "2/7"; no fact text
  shows a non-zero value as "0", a placeholder value that would
  print "0" is refused, and so is a modifier step that overflows or underflows,
  `text.range.<name>`), and rule N1 refuses a caption with a number character (by the
  toolchain's Unicode data and a pinned Unicode 18.0.0 Numeric_Type table) that does not
  come from a placeholder (`text.number.step.<n>`) unless the step is marked
  `"unchecked": "<why>"`. Steps can state `check` claims
  (`{"value", "eq" | "lt" | "gt", "tol"?}`, as in lessons) that the engine proves before
  it accepts the document (`check.failed.<name>` when false, `check.fact.<name>` when the
  fact does not exist); each check is its own claim, shown with its exact target. Truth tiers (Solved, Built,
  Described) are computed by the engine for every motion, caption, title and check
  (`claims`, `legend` with chip texts, `motionTier`, `describe(id)` with a "not checked"
  list per motion source): an `input` scale other than ±1, a `follow` ratio and what they
  feed are Built, and a title with a typed number is Described. A `tier` key anywhere in
  a v2 document is refused (`tier.key`). Every document, v1 or v2, is linted after it
  compiles (`warnings`): `joint.idle.<id>` (a jointed part that nothing moves),
  `frame.child.absolute.<id>` (the double offset, confirmed by geometry: the child misses
  its parent as placed but would sit near it if its `at` were read as world
  coordinates), `frame.child.far.<id>` and
  `frame.axis.off.<id>` (a turn axis that misses its own part; v2 `"offAxis": true`
  marks it intended). v2 parts can state `"expect": {"axisWorld": …, "upWorld": …}`,
  refused when the model does not match (`expect.axis.<id>`, `expect.up.<id>`).
  `readBack` describes every part in plain words (world position, "turns about a
  horizontal axis (+X)", parent frame, up). `MGSolidProfile.strict` and
  `marty-solid check --strict` (the model-harness profile) refuse idle joints and turn
  axes that miss their own part, which the plain API only warns about (`applying` takes
  the profile too); the child-frame heuristics stay warnings in every profile; `check`
  also prints warnings, facts, legend, `stepFacts` (which fact filled each placeholder),
  `notChecked` and the read-back. `docs/SOLID-3D.md` gains a frames and "up"
  conventions section (child `at` / `rot` are relative to the parent; lay a shaft down
  with `rot`, keep the joint `[0, 0, 1]`), the most common silent error in recorded
  model runs. New v2 worked example `horizontal-reduction.json` (15/40 teeth on shafts
  along X). Every shipped v1 example passes `--strict` with no warnings.
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
  `snapshot.bytes`, a NaN or infinite number is `snapshot.number`, and deeper than 64 levels (`MGLimits.depth`, see
  above) is `snapshot.depth`. Line timing on restore follows the
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
