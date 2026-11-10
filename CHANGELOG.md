# Changelog

## Unreleased

- Engine fixes from the failures recorded in prompt-to-3D round r2k (one hidden view per refusal, a thrust arrow inside
  its own forearm, a hidden forearm "nearer" to a label, captions without their arrows, a weight arrow at a thigh, a
  board table under the title band, and a legend line that read as verified facts).
  - **Every view of a hidden arrow** (`MGSolidDocument.arrowViewScan`, `MGArrowViewScan`). The check reports test each
    hidden arrow in every framed step or beat still, also those that do not list it, and add `views` (`hidden`,
    `clear`, `every`, `hiddenCameras`, `tested`) to its issue. `fix` and `repair` name every other view that hides it
    and say "hidden in every `front` view" or "hidden in every beat still". Before, each refusal named one beat and a
    model moved the arrow from beat to beat.
  - **Arrow drop, cause `part`.** A force or flow arrow that is fully hidden in a still whose camera cannot see its
    tail's part (that part alone; the unit shows elsewhere) is dropped (`annotation.arrow.dropped.<id>`), not refused
    with `noSuggest` code `tail`, which left no way out. An arrow whose tail's part shows is still refused.
    `arrowDrops` entries add `cause` (`unit` or `part`).
  - **The off-part test skips hidden parts.** `annotation.anchor.off.<id>` no longer finds a part nearer in a view
    that hides it, so a part hidden in every view that shows the label never counts.
  - **`annotation.arrow.orphan.<id>`, `annotation.arrow.caption.<id>`** (new warnings, never refused): every still
    that lists an arrow drops it, or a step's or beat's text names the force of an arrow its still drops (gravity:
    "weight", "gravity"; force and flow words of the arrow's text). The reports add `arrowDropNotes` with repairs.
  - **Centre-of-mass anchor** `{"point": "centreOfMass"}` (optional world `"offset"`), at force arrows' ends: the
    volume-weighted centre of every part's mesh (uniform density), posed at each view. **`annotation.arrow.weight.<id>`**
    (new warning): a gravity arrow placed off the body whose line of action misses that centre by more than 5 % of
    the model's diagonal; the report's `weightPlacements` suggests the centre-of-mass anchors with the authored vector.
    `anchor.point` and `anchor.form` name the new form.
  - **`board.clip.<id>`** (new explainer warning): a beat's board pane at 1280 × 800 cuts a board item (it leaves the
    pane less 8 px). The report's `boardClips` gives the overflow and the exact move of the item's `at`.
  - **Legend wording.** The Solved group says how many of its claims are animation ratios (Solved motion claims):
    "Solved 18 (15 animation ratios)", "Solved 3 (animation ratios)" when all are (`MGLegendText.solved`). One string
    for the stills, `story.mp4`, the SwiftUI views and the reports; the counts do not change.

- Docs and tests: the determinism promise now says exactly what is byte-identical and what is not
  ([SOLID-3D.md, Determinism](docs/SOLID-3D.md#determinism)).
  - **Byte-identical in every run:** parse and refusals, solved facts, check reports, cameras, framing, annotation
    layout, story plan and frame timing, `snapshot.json`, and the render manifest except `renderSecondsPerFrame` (wall time) and
    the `bytes` and `sha256` of PNG, GIF and MP4 files. Images without a 3D view are byte-identical too.
  - **3D pixels:** identical within one renderer instance; between processes SceneKit's physically based shading can
    change them (cause inside SceneKit, not in the engine's data). Measured on 2026-11-10 at d35e0c3: 164 stills of 21
    documents at 1280 × 800 in five fresh processes; 22 byte-identical; per still the largest difference has median 3
    levels and maximum 99, the differing share is at most 5.02 %, and at most 0.0112 % of the pixels are more than 16
    levels apart. The largest differences are two local spots (gear teeth seen through a small hole in an anodized
    carrier, a 14 × 8 pixel patch in a thin gap).
  - **New test** `testCrossProcessOutputIsByteIdenticalExceptBoundedPixels` (Solid3D): three fresh processes per
    document (two shipped documents in debug builds, four in release builds). Exact: check reports, the manifest
    (without wall time, image and video `bytes`/`sha256` and the executable hash) against committed goldens in
    `Golden/render` (cameras, framing, story plan), snapshot files (must exist) and `board-0.png` by SHA-256. Bounded
    3D stills: mean pixel difference at most 0.1622 levels, at most 0.1082 % of the pixels more than 16 levels apart,
    at most 10.03 % differing pixels (the higher of local and hosted CI maxima × 1.5, 2, 2). Every existing exact
    check is unchanged.
- Engine fixes from the remaining failures recorded in a prompt-to-3D evaluation round (r2j): figures cut by the frame
  or under the title band, wrist-ring engines too small to read, and full-width numbers.
  - **Subject-first framing** (one rule for stills, story hold frames, `MGSolidRenderPlan`, the SwiftUI pane and the
    check report: `MGSolidFraming.clearView`). A still's subject (`MGSolidFraming.subjectParts`) is its explicit
    `focus`, or else its highlighted, section and annotated parts plus, in a posed step, every chain the pose moves (a
    raised arm and its jet). The camera takes the closest framing that keeps the subject whole together with every
    target the still draws (label anchors, pointer tips, arrow tails and heads), so no label is left "(off view)".
    Context may be cut at the safe window's edges; the renderer clips the model to the safe window
    (`MGSolidRenderer.render(width:height:clip:)`, used for every still and story frame), so nothing is drawn under the
    title or caption band. The camera stays outside the box of every solid context part. A still that draws a label,
    pointer or arrow keeps main's camera (`MGSolidFraming.mainRule`, manifest `"mainRule": true`) when the subject
    camera would hide one that main's camera shows (any still: focus, inferred subject or whole model), so framing
    alone never refuses a document accepted before (a test checks every shipped document; the published AI lesson
    passes `check --strict`). `MGSolidFraming.camera`, `MGSolidFraming.framing` and `MGSolidRenderer.frame` return this
    effective camera. The check reports add `stillPlacements`, the label placement at each still's effective camera
    (`placements` keeps the legacy default camera). The whole-model rule keeps the
    title band free. Causes found: at main a focus fit read only the focus and anchors (a head above a highlighted back
    pack sat under the title band); PR #51's first fix widened the close-ups until nothing was cut, which shrank the
    subjects; this replaces it.
  - **`framing.subject.small.step.<n>`, `framing.subject.small.beat.<n>`** (new warnings, never refused): a subject
    group misses a floor, on every still with a subject: a 25 % fill of the safe window (`subjectFill`), and per group
    0.5 % of its pixels (`subjectAreaShare`) and a 24 px shorter side at 800 px high (`subjectExtentPixels`). A group
    is an instance named by its instance id (less its explicitly named parts), or one named part: a part named
    explicitly anywhere (focus, highlight, annotation target) is always measured alone, also beside its named
    instance. The check reports add `subjectFloors` with the measure and exact repairs:
    `split`, `subset`, `ghost` (the complete list, the view's own ghosts kept, also from the public API by default) and
    `annotate` (the step's list without the far annotations that widen it).
  - **Crops from triangles.** `MGSolidFraming.cutParts` tests every triangle in camera space against the five view
    planes, so a face that spans the view with every vertex outside it, or crosses the near plane, counts. The render
    manifest lists a step still's clipped parts as `clipped`. The coverage raster (`MGStillRaster`, quarter size, one
    per still for the subject floors and the small units) clips triangles to the near plane instead of dropping them,
    so a near occluder still hides what lies behind it.
  - **Exact repairs.** Repair lines write ids as complete JSON strings (`MGExactRepair`) and never cut a JSON
    fragment; when it does not fit the 400-scalar line, the line names the structured field that holds it.
  - **`unit.small.<id>`** (new warning, never refused): a unit (component instance or plain part) that a shown label or
    arrow rides on, or that a step or beat highlights, covers fewer than 0.05 % of a 1280 × 800 frame (512 px) in every
    still that shows it, measured by a quarter-size depth raster of the solid parts (`MGSmallUnitRules`,
    `MGSolidDocument.smallUnits`). The check reports add `smallUnits` with the most pixels, the still and the repair
    (a focused view, a larger size, a closer camera). New `MGSolidDocument.framedStills()` and
    `MGExplainerFrame.beatStills(_:)` give every still as the render tool frames it.
  - **Unicode NFKC for rule N1 and declared names.** Text is put in NFKC form (one grapheme at a time, with a map
    back) before it is split into tokens (`MGSolidFacts.typedNumberOffsets`), in captions, labels, titles, board
    cells, `add` and `set`. A token matches a declared name when the NFKC forms are equal (exact, case-sensitive), so
    full-width "Ｆ－３５" matches "F-35"; "㎏Mk4" and "kgMk4" get one answer. In other tokens, a character is a
    number when its normalized form holds a digit or the original has a numeric value ("Ⅻ", "²", "½", Arabic-Indic
    digits, "㋀"). A name whose original form holds a number character other than an ASCII digit ("Ⅻ2", "Mk²",
    "Ａ３２０") is `names.number.<n>`; other names are kept in NFKC form ("Ｍａｃｈ２" is refused as "Mach2").
    Captions are shown as written.

- Engine fixes from four failures recorded in a prompt-to-3D evaluation round: pointers to a part centre, model names
  in text, force arrows that left their parts, and an empty board table.
  - **Pointers to a part centre end on the part's surface.** A pointer whose tip is `{"part", "point": "centre"}` (or
    `{"part"}`) is drawn to the first crossing of the part's mesh on the segment from its start to the centre
    (`MGSolidAnnotations.pointerTip`; a step's cut mesh when the step cuts the part). Before, its head sat inside the
    part, so the arrow rule refused every such pointer as hidden by its own target, with no checked move. The anchor
    checks still count only other parts for the centre, and strict still refuses a pointer that another part covers.
    The arrow suggestion search draws each candidate with the tip it gives.
  - **Declared names (rule N1).** A v2 assembly, and an explainer header, may list `names` (1–24 tokens such as
    "Mk4", "A320", "F-35"). A text token that exactly equals a declared name (whole token, case-sensitive) is not a
    typed number; an explainer's names also cover its solid's text. Nothing else is exempt: an undeclared "Mk4" is still
    `text.number.<where>`, and "Mk 4", "mk4", "Mk4s" and other numbers in the same text still count. A name must start
    with a letter, no number literal of N1's own scan may cover it, its leading letters may not be a unit or quantity
    word, else `names.number.<n>` ("2e3", "1e-3", "120N", "0x1F", "3D", "Mach2", "USD120", "RPM120"); a name with no
    number character is `names.token.<n>`. `add`, `set`, captions, labels, arrows, dimensions, titles, board cells,
    bar labels, control labels and template params all pass the names (the N1 functions take them as a required
    argument). New reasons `names.count`, `names.text.<n>` (both with `limit`), `names.token.<n>`, `names.number.<n>`.
    Marty fills `names` from its research rows.
  - **Arrow tails.** A suggested, re-checked or auto-applied move of a force or flow arrow never takes its tail (the
    end on a part nearest that part's box) farther from its part (`MGAnnotationArrowRules.keepsTail`): a tail within
    the precision epsilon of its part stays within it (an absolute bound); any other tail may not move farther off. When no move is left, `noSuggest`
    has the new code `tail` and strict refuses. Before, moves of a quarter of the blocker's size or more floated thrust
    arrows 220–440 mm off their engines.
  - **Arrow drop.** A still whose camera cannot see the unit (component instance) an arrow's tail rides on drops that
    force or flow arrow: at most 10 % of 48 unit samples seen, where a sample counts as seen when the first surface on
    its line of sight is the unit's own (`MGSolidFraming.clearView` → `MGSolidClearView.arrowDrops`,
    `MGSolidDocument.arrowDrops`, `MGArrowDrop`). The one gate `checkedAnnotations` leaves dropped arrows out
    (`MGSolidView.arrowDrops`). An explainer beat has one drop set, decided at its framing for the whole 1280 × 800
    content area (`MGExplainerFrame.beatArrowDrops`), which its still, story frames, SwiftUI pane and check report all
    use. New warning `annotation.arrow.dropped.<id>` (never refused); the check reports add `arrowDrops` when a still
    drops one, and `marty-solid render` adds `arrowDrops` to the still's manifest record and story beat.
  - **Claims count only what is drawn.** An explainer's presentation record, claims and legend use the annotations
    each beat draws after its drops (`MGExplainerSession.displayedAnnotations`); under the show-all rule an arrow that
    every kept beat drops makes no claim. An assembly arrow that every still listing it drops makes no claim
    (`MGSolidDocument.undrawnArrows`). Before, a dropped arrow still counted ("Not checked 1").
  - **Empty tables.** A table with no data row (`MGItem.isEmptyTable`: a header waiting for its first `set`) is not
    drawn (`MGCanvasRenderer`) and does not open the board pane (`MGExplainerBoardPane.rule`, `boardShare`). The pane
    opens at the beat that fills the table, and the story slides it open (PR #45).
  - Golden files: only `docs/assets/jet-suit-ai/lesson.json` changes. Its check (standard and strict) now lists two
    beat-4 drops (`aL1` behind `eL2.casing`, `aR2` behind `eR1.casing`) in `arrowDrops` and `warnings`; it still passes.
    The arrow-visibility fixture `arrow-in-casing.explainer.json` now gets no move (`noSuggest` code `tail`).
  - docs/SOLID-3D.md: "Declared names", "Pointers to a part centre", "Why force arrows left their engines", "Arrow
    tails", "Arrow drop"; docs/EXPLAINER.md: "Empty tables", `names`, what the legend counts, the report's
    `arrowDrops`; docs/REASONS.md: the new reasons and warning.
  - Tests: `PointerCentreTipTests`, `DeclaredNamesTests`, `ArrowTailAndDropTests`, `EmptyTableTests` (synthetic
    boxes, gears and `microTurbojet`s; neutral names).

- Docs: the first AI prompt-to-3D lesson that meets the showcase bar leads the README and docs/SHOWCASE.md.
  - Question "How does the Gravity jet suit work?" (follow-up "How does the pilot steer?"), answered by Claude Opus 5.5
    through Marty `f2d7c5a` with research on; engine `dfc521a`; round 2j, run `r2j-opus-1`, accepted on try 3. All 4
    runs of the round and every try are listed (3 accepted, 1 refused; 1 of 4 met the bar).
  - New folder `docs/assets/jet-suit-ai/`: the accepted lesson JSON, the strict check output at `dfc521a`, the 9 beat
    stills, a poster (a copy of beat 2), the story video and the follow-up answer, all byte-identical to the run and
    render outputs; `PROMPT.md` (prompt, setup, tries), `FACT-CHECK.md` (the independent fact check, corrections
    C1–C13) and `provenance.json` (SHAs, file hashes, render command). The lesson is shown unedited; the corrections
    are listed, not applied.
  - The lesson still passes `marty-solid check --strict` at main (`5bae049`); at that commit the report is the same
    except the engine identity. Later engines change it: from PR #49 the check also lists two beat-4 arrow drops
    (`annotation.arrow.dropped.aL1`, `aR2`, warnings, still passing). New golden check files for the three new JSON
    files.
  - The hand-built jet-suit lesson stays as the reference, unchanged.

- SwiftUI solid pane uses the still's framing (follow-up from PR #37).
  - `MGExplainerController` (shown by `MartyGraphicsExplainerView`) now frames each beat with
    `MGExplainerFrame.solidClearView`, the function of the beat's still and its `story.mp4` hold frames, for the
    beat's step at the pane's aspect. Before, it framed the posed bounding box from the beat's preset with its own
    rule, so the app could show a different view than the rendered lesson: no focus framing, no automatic ghosts and no
    alternate direction. Now the pane gets per-step focus framing, the unblocked-focus rule and every preset (`backLeft`
    and `backRight` included), and it draws the beat's view with the still's automatic ghosts. For the same beat and
    pane aspect, the pane camera equals the still camera.
  - New: `MGExplainerFrame.solidClearView(_:view:stepIndex:aspect:)` (the `pane:` form calls it with
    `MGFrameRect.aspect`; a bad aspect frames as an empty pane does). `MGExplainerController.paneClear`, `paneView` and
    `cameraReset`.
  - The framed camera is the start pose of each beat. The learner may still orbit and zoom a solid without
    annotations. A new beat, a recompiled solid or a new pane aspect returns to the framed camera: the view builds a
    fresh scene view for each `cameraReset`, so the orbit, a camera SceneKit switched to and its pivot are dropped. The
    pane still cuts between beats. It adds no camera timing (the story's routed moves are not played live).
  - docs/EXPLAINER.md: "The solid pane in SwiftUI"; docs/SOLID-3D.md: the unblocked-focus users. Check reports, golden
    files and rendered outputs do not change (the CLI did not change).
  - Tests: every beat of the shipped explainers (`Examples/Explainers`, the docs fixtures with engines and a
    `microTurbojet`) and of the shipped turbofan model played as an explainer (its beats show automatic ghosts) gives the
    still's camera, unblocked-focus result and view in the controller; `backLeft` and `backRight` beats; a wall ghosted
    in the pane; same results in fresh controllers; each framing is a camera reset and a moved camera goes back to the
    framed camera.

- Back three-quarter camera presets and part-centre anchors.
  - **Camera presets `backLeft` and `backRight`** (`MGSolidCamera.presets`): three-quarter views from behind, yaw 135°
    and 225° (±135° from `front`), at `hero`'s pitch (28°). `backLeft` looks from behind on the +X side (`hero`'s side),
    `backRight` on the −X side. They take the same framing rules as every preset (per-step focus, unblocked focus,
    title-band fit). There are no aliases: `three-quarter-back`, `back-left` and other spellings are still
    `step.camera` / `view.camera`. `MGSolidCamera.presetNames` lists every name in a fixed order, and the catalog
    meaning of `step.camera` and `view.camera` (so the check report's `repair` line) now lists them all.
  - **`{"part": id}` anchors.** An anchor object with only `part` (no `offset`, no `point`) is the part's centre, the
    same as `{"part": id, "point": "centre"}`; every centre rule applies (anchor checks, strict refusal of a hidden
    centre, with a `suggest` when a safe candidate exists and otherwise `noSuggest` and its alternatives).
    Changed reason for an old input: `{"part": id}` alone was `anchor.form`; it is now
    accepted. Every other bad anchor shape is still `anchor.form`. The `anchor.form` meaning names the new form.
  - docs/SOLID-3D.md: a "Camera presets" table and the new anchor row; docs/REASONS.md: the three changed meanings.
    Check reports and golden files do not change (no shipped document uses the new names or the new form).
  - Tests: both presets frame their focus and the whole model inside the safe window, use the unblocked-focus rule,
    render with the framed camera and are accepted in a beat view; aliases are refused; `{"part": id}` parses as the
    centre and gets the same strict report as the centre form, with a suggestion that passes; fresh-process checks
    give the same text.

- Pane slide in explainer story videos (`MGPaneSlide`).
  - A beat whose pane layout differs from the previous beat's (the board pane opens, closes or changes width) no longer
    cuts. During the camera move into the beat the pane edges move with the move's eased share, in whole pixels: the
    solid pane eases between full frame and split, a board pane grows from or shrinks to its outer edge, and the board
    fades in or out, drawn at its own size and centred in the pane. The camera moves as any move does (straight or
    routed, swept boxes, PR #44) and is fitted to the current solid pane on every frame: the 3D image is rendered at
    the pane's current pixels, and the field of view widens when the pane is narrower than the blended aspect; the
    camera position never changes. At share 0 and 1 the panes are exactly the two beats' layouts, so hold frames keep
    the stills' layouts and cameras exactly. The board shows the previous beat's state until the hold starts (an
    opening pane fades it in, drawn for the new pane, while its title-band line fades out); the caption, labels and
    claims wait for the hold, as before. Only a move with no clear path still cuts.
  - Manifest: a story beat whose layout changes gains `layout` `{"path": "slide" | "cut", "change": "open" | "close" |
    "resize", "seconds"}`; its `path` and `pathReason` give the camera path (before: `cut`, `layout`), and `cut` is
    false unless the move cut. `cutReason` `layout` no longer occurs in `marty-solid render` output.
    `MGStoryPlan.routes(_:beats:plan:layout:stage:)` keeps its `layout` argument for hosts that cut on a layout change.
  - docs/EXPLAINER.md: "Pane slide in the story video", and how the story (the move's 0.6 s or 1.0 s) and the SwiftUI
    view (0.35 s, `paneAnimationSeconds`) animate the same layout change. Check reports and golden files do not change.
  - Tests: a synthetic explainer whose board pane opens at beat 2 and closes at beat 4 renders with no cut; hold
    cameras equal the stills' cameras; no caption, label or claim of the new beat shows during a slide; same output in
    fresh processes.

- Routed story camera moves and strict arrow visibility.
  - **Routed moves** (`MGStoryPlan.routes`, `MGStoryMove`). When the straight camera move between two beats would pass
    through a part the move draws, fixed alternative paths are tried before the story cuts: a pull back along the start
    camera's view (1.5, 2, 3 and 4 times its distance, and the distance that leaves the model's bounding sphere), an
    arc about the model's bounds centre at a radius no smaller than either camera's distance from it plus a clearance
    (three radii), and the two together; the first clear path in that order is taken (at most 24 per move). Each leg
    plays with the move's own interpolation and is tested with the exact segment-versus-box slab test of PR #37 over
    bounded chords with the proven chord error; each chord's growth is the near plane at that chord's larger camera
    distance (chords split so the distance changes by at most 10 %), not one growth at the move's largest distance. Each
    part's box is swept over the move's actual frames (the spin share and pose blend of every frame,
    `MGStoryPlan.movePose`, which the render tool also draws with), grown by the largest corner step between frames;
    without the frames, a beat whose parts move cuts (`motion`). Only parts the move draws solid block it: hidden
    parts, ghosts and glass do not (the coverage rule of the anchor checks).
    A routed move takes 1.0 s (`MGStoryTiming.routedTransitionSeconds`, at most half the beat) instead of 0.6 s; the
    beat's length does not change. Every path starts and ends exactly on the beats' still cameras, so hold frames are
    unchanged. During a move, a part the previous beat ghosts is drawn as a ghost too (`MGSolidView.moving(from:_:)`).
    The story manifest's beat records gain `path` (`straight`, `pullback`, `arc`, `combined`, `cut`), `pathReason`
    (`clear`, `blocked`, `layout`, `motion`, `untested`), `blockedBy` and `moveSeconds`, and the record gains
    `routedTransitionSeconds`. `MGStoryPlan.blockedMoves` stays in the library with its PR #37 rule; the render tool
    uses `routes`. New API: `MGStoryMove`, `MGStoryBeatShot`, `MGStoryPlan.routes(_:beats:layout:stage:)`,
    `MGStoryPlan.routed(_:)`, `movePose`, `moves`, `cuts`.
  - **Arrow visibility** (`annotation.arrow.hidden.<id>`, `annotation.arrow.untested.<id>`). In every step or beat still
    that shows an arrow (force, flow, motion or pointer), 16 points along the drawn shaft and 3 along the head are
    tested from the still's camera with the line-of-sight rule of the anchor checks (blocking coverage, cut exception,
    sample-relative precision), with no own-part exception: an arrow inside its own casing is hidden. Less than half of
    the samples visible, or fewer than 2 of the 3 head samples, is `annotation.arrow.hidden.<id>`: standard warns,
    the strict check report refuses (after the anchor refusals) with the view, the visible share and the part in the
    way. A view's 3,000,000 tests that run out leave the arrow `annotation.arrow.untested.<id>` (strict refuses). The
    report lists `arrowIssues` and, on an arrow refusal, `arrow`, with `suggest`: a move of a force or flow arrow (both
    ends by one offset) or of a pointer's start that shows it in every view that shows it, from fixed directions and
    sizes, that keeps a force or flow arrow's vector (direction and length) in every view that shows it, re-checked once
    applied as anchor suggestions are (`framing`, `conflict`, `form`); none keeps it: `noSuggest` (`pose`); a motion
    arrow gets `noSuggest` (`motion`). All searches of a report, retries included, share one 64,000,000-test budget.
    Last, every printed suggestion of a report, anchors and arrows together (also a union of one family), is applied to
    one copy and checked again with every anchor and arrow rule (`MGSuggestionUnion.verifyTogether`); a suggestion
    that conflicts in the union is dropped (`conflict`, with `other`), and the rest is checked again until stable, so
    a model can apply every printed suggestion at once. New API: `MGAnnotationArrowRules`, `MGAnnotationArrowIssue`, `MGAnnotationArrowSuggestion`,
    `MGArrowVisibility`, `MGSolidDocument.stepCheckViews`, `stepArrowIssues`, `MGExplainerFrame.beatCheckViews`.
  - Example fixed: in the jet-suit lesson, arrow `aTL2`'s head was behind the pack in step 2 (73 % of its samples
    visible, head hidden). It now uses the check's suggested move (135 mm toward the step's camera, same direction and
    length). Its stills, story video, poster, check report and receipt were made again.
  - Golden files: the check reports gain `arrowIssues` (and `arrow` on an arrow refusal), stripped like the other added
    fields; the jet-suit document's golden files hold the fixed file's output. Test inputs:
    `docs/fixtures/arrow-visibility` holds a synthetic explainer with an arrow inside an engine casing (neutral names).

- Repair-friendly check reports.
  - **Anchor suggestions.** Every `annotation.anchor.off.<id>` and `annotation.anchor.hidden.<id>` issue in
    `anchorIssues` (and the refusal's `anchor`) gains `suggest`: an anchor `{"part", "offset": [x, y, z]}` (the
    part's own frame, mm, rounded to 0.001 mm) that passes both anchor rules in every view that shows the label or
    pointer. The search casts rays from each view's camera toward sample points of the part and across a grid facing
    the camera, takes the first hit on the part (moved 0.05 mm into it), prefers the cut face of a cut part, sorts by
    distance to the authored dot, and keeps the first candidate that the check's own rule functions pass, as printed.
    A second, denser pass runs only when the first finds none. A suggestion is written in a form the parser accepts
    (an offset within ±4000 mm, or `{"point": "centre"}`), and it is printed only when a full re-check of the
    document with the suggestions applied (parsed, compiled and framed again) shows no issue for any suggested
    annotation and no new issue for any other annotation. A suggestion that keeps an issue, or that hides another
    annotation, is searched again (at most 2 retries; at most 6 re-checks in all); otherwise it is dropped with cause
    `framing`, `conflict` (with `other` naming the annotation it would hide) or `form`. When no candidate passes, `suggest` is null and
    `noSuggest` gives `{"cause", "code", "step", "beat", "by", "other", "samples", "alternatives"}` (for example
    `"part fully hidden in step 6"`, behind `back.casing`; leave the label out of that view's `annotate`, ghost the
    blocker, or change the camera). The searches are bounded (8,000,000 tests per search of one annotation, at most 3
    searches per annotation, 64,000,000 for all searches of a report, plus at most 6 full re-checks) and deterministic. `fix` names the suggestion and proposes `{"point": "centre"}` only when the rules pass
    it. New API: `MGAnnotationAnchorSuggestion`, `MGAnnotationAnchorView`,
    `MGSolidDocument.anchorSuggestions(for:views:)`, `stepAnchorViews(width:height:)`,
    `MGExplainerFrame.beatAnchorViews`, `MGAnnotationAnchorIssue.suggestion` and `repair`.
  - **Limit details.** Every refusal from a length, count or size limit (titles, captions, `say`, label and note
    texts, parts, steps, beats, notes, `annotate` lists, step and view id lists, component limits, document bytes,
    the mesh budget and so on; `MGSolidReasons.limitPatterns`, 62 patterns) now reports `limit`:
    `{"field", "actual", "limit", "unit"}`, plus `"minimum"` for a `1–N` rule; a number the engine does not hold
    exactly is `actualAtLeast` (it stopped counting at the first value over the limit, or the number is above 2^53)
    or `actualAtMost`, never a capped `actual`; an integer beyond 2^53 that JSON parsing keeps exactly is read rounded
    away from zero, so it too is a bound. `field` is a path into the document (`title`, `beats[2].say`,
    `parts[0].shape[1].plate.holes`, `solid.annotations.labels[4].text`, `solid.parts`). `parts.resolved` keeps `count` and `top`. The reasons
    catalog (`marty-solid reasons`) gains `"limit"` per entry; `MGSolidReasons.limitExempt` gives the cause for each
    bound that carries no detail. Every `marty-solid` component path (`component check`, `--component`) keeps `limit`
    and `repair`. New API: `MGSolidLimitDetail(field:actual:limit:unit:minimum:bound:)`, `MGSolidReport.refusalDetail`,
    `MGSolidIssue(_:part:limit:)`, `MGError.limit`, `MGAnnotationVisibilityDetail.limitDetail(prefix:)`.
  - **`repair`.** Each anchor issue and every refused report carries `repair`, one line built from the structured
    fields (at most 400 Unicode scalars, deterministic), for example `Label lComb (step 6) is hidden behind
    back.casing. Use anchor {"part": "back.combustor", "offset": [0, -30, 148]}.` or `title has 87 characters; the
    limit is 80. Shorten it to at most 80 characters (7 fewer).` A refusal without detail gives the catalog meaning.
  - Golden files: the refused reports gain `repair` and, for a limit refusal, `limit`; nothing else changed.
  - Test inputs: `docs/fixtures/anchor-suggest` holds two synthetic explainers with the geometry problems of the
    round-2f refusals (neutral names, no real-world claims); applying every `suggest` clears that annotation's anchor
    issues.

- Strict label and pointer anchors. In `--strict`, a label (its `at`) or pointer arrow (its tip, `to`) whose anchor a
  step or beat still does not show is refused: `annotation.anchor.hidden.<id>`, for an anchor occluded by another part
  (the watertight line-of-sight rays of the unblocked-focus rule, 3,000,000 triangle tests per view), on a hidden or
  ghosted part (automatic ghosts included), or off screen. A part blocks only when it is drawn with a coverage of 0.5 or
  more: view opacity times the material's own coverage (`MGMaterialPreset.coverage`; glass 0.22), as the renderer
  draws it. Every test runs in anchor-relative coordinates; a blocker hit that lies on the anchor's own part within a
  numeric-precision epsilon (`1e-6 × max(1, |p − anchor|) + 1e-4` mm; a coincident face of touching parts) is a tie,
  not an occlusion. An anchor on a part that the view's section cuts is not hidden by the parts inside that cut part (tested in
  the cut part's own frame) when it lies on the cut face or inside the cut. An anchor that a view's triangle budget
  leaves untested is `annotation.anchor.untested.<id>`: strict refuses it, standard warns. An anchor farther than
  max(5 % of its part's box diagonal, 0.5 % of the diagonal of the parts the views showing it draw) from its part's
  oriented box, or, at the pose of a view that shows it (in that view's geometry), nearer (beyond the precision epsilon) to another part's solid
  than to its own part's box, is `annotation.anchor.off.<id>` (a
  document warning, so the compile's strict profile also refuses it; the detail names the view and the nearer part).
  The nearer-part search is exact, stops early and counts every test against 3,000,000 per document; out of budget
  the anchor is `annotation.anchor.untested.<id>` (`"budget": "nearerPart"`), never off. The standard profile warns and keeps the hollow dot and
  dashed leader. Each step is framed as its 1280 × 800 still; each explainer beat as its still's solid pane (a
  speech-paced replay gives each beat's board pane). The check report gains `anchorIssues` (`id`, `kind`, `reason`,
  `cause`, `part`, `by`, `closer`, `closerDistance`, `budget`, `step`, `beat`, `point`, `distance`, `tolerance`, `fix`),
  `anchorUntested` and, for an anchor refusal, `anchor`; an explainer refusal's `location` names the beat and the cause.
  New API: `MGAnnotationAnchorIssue`, `MGAnnotationAnchorReport`, `MGAnnotationAnchorRules`, `MGMaterialPreset.coverage`,
  `MGSolidDocument.offPartAnchors`, `anchorIssues(view:params:camera:width:height:step:beat:stage:)`,
  `stepAnchorIssues(width:height:)`, `MGExplainerFrame.beatPanes` and `beatAnchorIssues`,
  `MGSolidReport.make(…, anchorViews:)` and `MGSolidReasons.reportStrictPrefixes`.
  - Example fixed: `docs/assets/jet-suit/jet-suit.json` was the only shipped document the rules refused. Its step 6 label
    `lComb` ("Combustion chamber") had its dot on the cut casing wall; the anchor moved from `[30, 0, 148]` to
    `[0, -30, 148]` on `back.combustor`, inside the chamber. Its step 1 label `lPilot` ("Schematic pilot") named the
    helmet but lay 2 mm outside it, inside the visor on the far side of the head; the anchor moved from `[0, -110, 0]` to
    `[0, 108, 0]` on `helmet`, its back, which faces the camera. All 7 stills, the poster, `story.mp4` (6.2 MB) and
    `check-strict.json` were made again with one build; the render receipt records the revision and the exact pixel
    comparison. Golden change: `docs-assets-jet-suit-jet-suit` (the fixed file's output: the two anchors, the file
    hash and the step 1 and step 6 reference placements) and `docs-assets-jet-suit-provenance` (the receipt's new line count and
    hash).
- Docs: `docs/assets/jet-suit/story.mp4` is re-muxed for fast start (`moov` before `mdat`; AVFoundation passthrough,
  no re-encode). All 1,890 decoded frames are identical; 5,657,049 bytes. `provenance.json` has the new hash and size; golden change:
  `docs-assets-jet-suit-provenance` (the receipt's new line count and hash).
- Docs: the jet-suit showcase now uses the sixth version of the hand-built lesson (`docs/assets/jet-suit/`, 59 lines,
  76 parts). Step 5 poses the pilot (both arms swing back, so the arm engines' exhaust is aimed back; the pose is
  schematic), exhaust plumes (an illustration) show in steps 2 and 5 only, highlights and explode take whole engines,
  long labels take two lines, and step 7 has a turn arrow on the shaft. The two PR #40 anchor changes (`lComb`,
  `lPilot`) are kept; no other anchor moved, and `check --strict` passes with no warnings. All 7 stills, the poster,
  `story.mp4` (5.7 MB) and `check-strict.json` were made again with one build, and `hero.png` is now published. No new
  fact; the source table in `SOURCES.md` is unchanged (its legend explanation now reads Solved 17). Golden change: `docs-assets-jet-suit-jet-suit` (the new file's output: file hash and
  lines, parts, read-back, annotations, legend Solved 17, steps, step views, show-only lists, placements, triangles) and
  `docs-assets-jet-suit-provenance` (the receipt's new line count and hash).
- Docs: the hand-built, fact-checked jet-suit explainer now leads the README and `docs/SHOWCASE.md`
  (`docs/assets/jet-suit/`: the 54-line JSON, 7 step stills, a 63-second story video re-encoded to 6.4 MB, a poster,
  the strict check output, a render receipt, and `SOURCES.md` with a label, source URL and date for every fact). A
  Claude agent wrote the JSON by hand from research checked by two independent AI model fact-checks; it is not an AI
  run of the engine from a prompt. No engine code changes.
- Step pose and step visibility, instance ids in step lists, instance explode, focus-sized motion arrows, two-line
  annotation text and a hero that keeps the title band free.
  - Step and beat-view `pose` (v2): `{"<instance>": {"with": {...}}, "<part>": {"rot": [ax, ay, az, deg]}}` moves parts
    for that step only (stills, story hold, framing, unblocked focus, snapshot). Each posed step is checked against a
    compile of the document with the pose applied: only placements may change (`step.pose.with`), no part of a gear
    solve or constrained mechanism may move, and the compiled motion and every engine fact stay the same
    (`step.pose.solved`), so captions and claims keep facts that hold at the pose. Gravity arrows, `expect`, dimensions
    and frame lints are re-checked at the pose. Reasons `step.pose`, `step.pose.ref`, `step.pose.key`, `step.pose.with`,
    `step.pose.solved` and the explainer's `view.pose.*`. `MGPoseParameters.placements`, `MGSolidStep.pose`,
    `MGSolidStep.poseParameters`, `MGSolidDocument.poseParameters(step:)` and `poseReadBack` are new; the check report
    gains `stepViews` (`posed`, `poseReadBack`, `hidden`) and `showOnly` when a step uses these keys. In `story.mp4` the
    camera move into a step blends the parts from the previous step's pose (`MGStoryPlan.placements`,
    `MGTransform.blend`), with a real render at every frame; the one annotation gate accepts only a step's own pose.
  - Step and beat-view `hide` and `show` (v2, 1–16 entries each): a part some step `show`s appears only in those steps.
    Hidden parts are not drawn, not framed, hide no other part and make no claim (`step.hide.both`, `step.hide.use`,
    `step.hide.claim`, `step.show.claim`, `text.hide.beat.<n>`). `MGSolidPartView.hidden`, `MGSolidView.hiddenParts`,
    `MGSolidDocument.hiddenParts(step:)` and `showOnly` are new; snapshots gain `hidden` and `posed` (v2).
    `MGSolidRenderer.worldBounds` and `frame` take an optional `hidden` set.
  - A component instance id counts as one entry in a step's `focus`, `highlight`, `ghost`, `hide`, `show` and
    `section.parts` and expands to all its parts; the expanded list is no longer limited to 16 (five `microTurbojet`
    instances light 55 parts). Before, the expanded list of `focus`/`highlight` had to fit in 16, and `ghost` and
    `section.parts` did not take instance ids.
  - A top-level `use` entry in a v2 assembly may take `explode`: it is added to every root part of the instance
    (`component.use.explode`).
  - Motion arrows (turn and line) take the step's focus size (`MGSolidDocument.motionArrowDiagonal(step:)`), so a small
    shaft's turn arrow no longer covers a close-up cutaway. Golden change: the `annotated-winch` check report's
    `placements` for step 5 (`aLift` box), from the shorter automatic arrow length.
  - Annotation text may be 60 Unicode scalars (was 40; authored 240); over 40 it draws on two lines
    (`MGAnnotationLayout.lines`, `lineScalars`), with the box at most 40 scalars wide and two rows high. A one-line text
    keeps its earlier box. Golden change: the jet-suit check report's step 4 `placements`, where two off-view callout
    rows now wrap to two lines.
  - `hero.png` keeps the title band free: its earlier framing stays only when the model clears the band, else it is
    fitted. Hidden parts are left out of every framing rule.
  - Facts at the pose and hidden facts: every geometry fact a posed step or beat displays (caption, checks, title,
    annotation and board text), and every `check` of any step or beat, must hold over the step's whole motion domain
    at its pose (its spin, explode and placements); a `dim.<id>` that does not is refused (`step.pose.fact`,
    `view.pose.fact`, naming the fact, also on host edits and restore). A displayed fact of a hidden part is refused (`step.hide.fact`, `view.hide.fact`); the title
    and board text may not show a fact of a part that any view hides. In an explainer whose views hide parts, the legend
    counts a part's motion only once a presented beat displayed it (snapshot `shownMotion`); a part every view hides
    makes no motion claim. Annotation text may not hold a character of more than 8 scalars (`text.grapheme`), and
    `MGAnnotationLayout.lines` cuts any line over 40 scalars with "…".
  - docs/SOLID-3D.md: the readability guarantee notes that `--size` accepts heights only up to 2160. docs/SHOWCASE.md
    notes that the winch stills predate the focus-sized motion arrows.

- Inside views that are not hidden, a whole jet engine in one `use`, and repair detail for `parts.resolved`.
  - Unblocked focus (`MGSolidFraming.clearView`, `MGSolidClearView`, Foundation only): after a step is framed on its
    focus, rays from the camera to at most 48 focus samples find the parts in the way. A part outside the focus context
    that hides more than 5 % of the samples is drawn as an automatic ghost in that still and story beat only; when a
    context part is in the way, or a section step does not face its cut, the fixed directions `opposite`,
    `quarterLeft`, `quarterRight` and `raised` are tried in order and the first clear one is taken. The render plan
    (`MGSolidRenderPlan.cameras`, new field `clear`), the explainer pane (`MGExplainerFrame.solidClearView`;
    `solidCamera` returns its camera) and `story.mp4` hold frames use it. Still and beat records gain `autoGhost`,
    `occluded`, `focusSamples`, `view` and `facesCut`; `offView` now also counts the focus samples still hidden.
    `MGSolidView.ghosting(_:)` is new. Shipped example cameras that change: only steps whose focus was really hidden or
    whose section faced away (see the PR for the list).
  - Story moves (`MGStoryPlan.blockedMoves`): a camera move that would pass through a part's box (grown by the near
    plane) cuts to the beat's camera. The test is an exact segment-versus-box slab test on the played path: one segment
    for a straight move; for a turn or zoom, at most 1,024 chords with the proven chord error added to the box growth.
    Story beat records gain `cut` and `cutReason` (`layout`, `blocked`).
  - Title backdrop: stills and story frames draw a dark backdrop (88 % black, soft fade below) under the title band's
    text, so geometry in the band cannot wash out the title, the legend line or the legend corner (at least 4.5:1,
    tested over a bright render and over pure white). The legend corner and an explainer's board line are covered
    also where a tall frame puts them below the band. The caption band is now 84 % black (was 55 %), and the board
    line is semibold in full ink, and the legend line is medium weight at 85 % ink (was regular, 60 %). Every glyph's
    interior stroke rows of the title, legend line, legend corner, board line and caption keep 4.5:1 for frames at
    least 1280 × 720, up to 3840 wide, aspect 0.5–2.0 (documented in SOLID-3D.md).
  - The clear-view ray test is watertight (Woop, Benthin and Wald 2013, with a half-open tie rule): a ray through a
    shared edge or vertex counts once, so the inside test of a closed part is exact.
  - Board pane width (`MGExplainerFrame.boardShare`, `boardReferenceSize`, `contentArea`, `paneGap`): side by side, the
    board pane fits its content, 28–50 % of the split width (55 % for a primary board), drawn at its reference pane's
    scale; the same in stills, `story.mp4` and `MartyGraphicsExplainerView` (`MartyGraphicsView.viewportFit(_:)`,
    `MGViewport.resized(to:)`). `MGExplainerFrame.panes` takes an optional `boardShare`; without it the earlier split
    stays to the pixel. Split beat records gain `boardShare`.
  - `microTurbojet` built-in component: intake lip, centrifugal compressor, vaned diffuser and shaft tunnel, annular
    combustor, nozzle guide vanes and turbine wheel, nozzle, shaft, two bearings and a casing (11 parts); parameters
    `diameter` 60–300, `length` 120–900, `cutaway` 0/1; anchors `intake`, `exhaust`, `mount`, `input`, `compressor`,
    `turbine`; checks `bore` and `fits`. Shaft, compressor and turbine turn together (Solved); thrust is not modelled.
  - `parts.resolved` reports add `limit`: `{"count", "limit": 96, "top": [{"id", "use", "parts"}]}` (up to five `use`
    instances, most parts first, ties by id), in assembly and explainer reports (`MGSolidLimitDetail`,
    `MGSolidIssue.limit`, `MGExplainerIssue.limit`). The reason stays one token.
  - Component expansion may now make up to 96 wire parts (`MGSolidLimits.expandedParts`; authored `parts` keep 1–48),
    so five `microTurbojet` engines, a mannequin and a pack (68 parts) fit. `parts.count` above 96 expanded wire parts.

- Explainers that look good on video: an adaptive board pane, a story video, a documented mannequin back frame and
  repair detail for `annotations.visible`.
  - Adaptive board pane (`MGExplainerBoardPane`, `MGExplainerSession.boardPane`, Foundation only): in an explainer
    with a board and a solid, a beat whose shown board has only `text` items gives the solid the whole frame, and the
    board's texts move to the title band. The rule reads the shown 2D state (`state`). `marty-solid render` stills,
    `story.mp4` and `MartyGraphicsExplainerView` use it; the SwiftUI pane slides in and out over 0.35 s and changes at
    once with Reduce Motion. Each explainer beat's manifest record gains `boardPane`. Example renders: no change for
    `gears-mixed` (its board has a table in every beat).
  - Story video (`MGStoryPlan`, `MGStoryTiming`): `marty-solid render` writes `story.mp4` for an assembly with steps
    and an explainer with beats: each beat held 3–9 s (1 s + caption scalars / 15, or the spin time), with its
    caption, view, highlight, annotations and framed camera, a 0.6 s eased camera move between beats, the beat's spin
    at 4 s per turn and the legend line in every frame; 30 fps by default (`--story-fps 10|30`), at the still size,
    at most 3,600 frames (`story.frames`, refused before any file is written; `--no-story` skips the story). The
    manifest record gives `fps`, `frames`, `seconds`, `transitionSeconds`, `holdSeconds` and each beat's `start`
    and `seconds`. New reasons `story.rate`, `story.beats`, `story.frames`.
  - During a beat's hold the story camera is exactly the camera of the beat's still, for the same layout
    (`MGStoryPlan.camera(frame:beatCameras:)`). Explainer pane rects are whole pixels (`MGExplainerFrame.panes`) and
    the solid pane is fitted for its own pixels (`MGExplainerFrame.solidCamera`). Labels are hidden while the camera
    moves between beats; when the explainer's pane layout changes between beats, the story cuts instead of moving. Step and beat still records and the story's beat records give `camera` and `offView`.
  - Components may describe their anchors (`anchorAbout`: anchor → one line, 1–120 scalars; `component.anchorAbout`),
    and the catalog lists it (about 6.2 KB for the built-ins). The `mannequin` describes all eight anchors; its
    `back` frame's origin is on the torso surface (+Y out of the back), so a pack whose shape starts at y = 0 touches
    the torso. No geometry changes. There is no `chest` anchor (the component has the maximum of 8 anchors).
  - Annotation visibility refusals add `visibility` (`annotation`: the first annotation over the limit, `count`,
    `limit`, `cause`: `nosteps`, `unannotated`, `step` or `beat`, and `step` or `beat` 1-based when one is at fault)
    to `annotations.visible`, `step.annotate.count` and `view.annotate.count` reports; an explainer report also sets
    `location.id` and `location.detail`. Reasons stay one token. Other refusals keep their exact keys.
  - In an explainer the visibility limit of 12 applies per beat: a solid with more than 12 annotations is stepped
    from its statement on (each beat shows only its own `view.annotate` list, at most 12; the views before the first
    beat and beats without a list show none). With 12 or fewer the earlier rule stays, so existing documents do not
    change. An explainer solid with 13 annotations spread over beats was refused before (`annotations.visible`) and
    is accepted now.
  - Explainer annotation claims follow what is displayed: whenever the beats choose their labels (some beat has
    `view.annotate`, at any count, or more than 12 annotations), the legend counts an annotation only once a presented
    beat displayed it, frozen at presentation (`MGShownAnnotations`, `shownAnnotations` in the snapshot, checked on
    restore); the overlay and the legend read one function. A whole document with any `annotate` list is stepped from
    its solid statement on, and a stream keeps the mode once it accepts such a view; the mode is saved in the snapshot
    (`chooseLabels`: `true` or absent, else `snapshot.labels`) and restored as saved, also after the only beat with a
    list was refused; an older snapshot without it derives the mode from every beat it knows. A new `explainer` header in the same
    session starts without the mode of the explainer it replaces. The show-all rule (no list, at most 12) still counts every
    annotation. Changed test
    expectation: in the mixed annotated explainer, the label of beat 2 counts once beat 2 is presented.
  - Story frames: a beat's caption, labels and board claims appear when its hold starts; during a camera move the
    caption band is empty and the board keeps the previous beat's state (`MGStoryPlan.holds`, `caption(frame:cuts:)`,
    `holdStartFrame`; the manifest's beats gain `holdStart`). The legend and its notes show in every frame. Spin times
    are clamped before they become frame counts.
  - Test expectations changed: `marty-solid render` on `gears-mixed` and `planets-2d` now also writes `story.mp4`.
    No golden report file changes.

- Fix: the explainer legend is presented-only. It counts the claims of exactly what the learner was shown, from
  the states that were actually presented: the board, each set-up command, each presented beat (as presented) and
  each accepted host or learner change. Before, it read 2D item claims from the projected and shown states only. So
  an item that one beat added and a later beat removed dropped out: a noted table that beat 1 adds and beat 2 removes
  gave "Solved 2" with no `Given`, and now gives "Solved 2 · Given 1". Also, a beat that waited or was still open
  already counted its items, captions and checks; now they count once the beat is presented (`finishNow()` presents
  them).
  - The lesson hands every newly shown state to the explainer. The explainer freezes the claims of its 2D items at
    that moment: ids in first-shown order, each with the set of tiers its displayed numbers had. The displayed content
    is the effective one (wire entry plus `over` entries in order), so a superseded override does not count, and a
    past claim keeps its tier when the board changes later. A command refused alone at presentation adds nothing.
  - Beat claims follow the same rule: while a beat is the presented beat, each shown state adds the tier of its
    caption and of each check. A past beat's caption and checks take the lowest frozen tier ("Checked" with it); the
    presented beat's stay live (they follow the board, and a false 2D check leaves the legend). The snapshot stores
    them (`shownBeats`, at most 16 beats with a caption and 8 checks, 3 tiers each; the cap grows by 5,776 bytes);
    `restore` checks their structure (`snapshot.shown`) and, without `shownBeats`, freezes each presented beat on the
    state shown now.
  - The explainer snapshot stores the record (`shown`: `[{"id", "tiers"}]`, at most 1024 ids with 3 tiers each; the
    snapshot cap grows by 81,936 bytes for it). `restore` checks its structure only (`snapshot.shown`: closed keys,
    each id once and in the id history, known tiers, every item shown now); it does not recompute past claims, so a
    valid history whose values are gone still restores. It also refuses a `presented` beat that is still queued,
    after the lesson's beat, dropped or unknown (`snapshot.presented`). A snapshot without `shown` restores with the
    state shown now as the record.
  - `marty-solid render` draws the legend of a copy of the session after `finishNow()` (every beat presented). Before,
    it used the legend at beat 1.
  - Changed results: a `.speech` session at beat 1 of `gears-mixed` (and its snapshot) now reads "Solved 4" until beat
    2 is presented, not "Solved 6". `check` presents every beat, so the golden files are byte-identical. 3D motion and
    annotation claims come from the whole compiled solid and do not change. See
    [EXPLAINER.md](docs/EXPLAINER.md#what-the-legend-counts-presented-only).
- Render upgrades for AI-written explainers: per-step camera framing, an MP4 loop and two built-in components.
  - Framing (`MGSolidFraming`, Foundation only, used by `MGSolidRenderPlan.cameras(_:width:height:)`, `marty-solid
    render` and `MGSolidRenderer.frame(_:document:aspect:)`): a step that lists `focus`, or highlights parts or shows
    a section, is framed on them (highlight and section parts with the parts that touch them, plus the step's
    annotation anchors) from the step's camera preset and `orbit`, filling 88 % of the safe window. A `focus` list is
    always framed exactly; inferred context larger than 75 % of the model uses the whole-model rule. The fit keeps
    every framed point beyond the renderer's near plane (`MGSolidFraming.nearPlane(distance:)`, at least 0.5 mm). Other stills
    keep the earlier bounding-sphere framing unless a part or annotation anchor leaves the image or enters the
    caption band; then they are fitted. The caption band (and, for fitted stills, the title band) is reserved
    (`MGSolidRenderPlan.bands(width:height:)`). Loop frames move back by one shared factor when any frame would cut
    the model. The fit reads posed mesh vertices (200,000 at most, sampled with extreme points beyond that). The
    renderer's far plane now reaches the farthest corner of the posed model. Step `focus` was parsed but unused
    before; it now names the parts the camera frames.
  - Changed renders of the shipped examples (cameras compared shot by shot with the earlier rule at 1280 × 800):
    `propeller` unchanged. Stills and loops that were cut or under the caption band are refitted (smaller):
    `annotated-winch` hero, steps 1–5 and the loop (×1.218); `horizontal-reduction` hero, exploded, steps 1–3 and 5
    and the loop (×1.195); `idler-gearbox` steps 1, 2 and 6 and the loop (×1.137); `planetary` steps 1–3 and 5;
    `planetary-components` steps 1–5; `slider-crank` steps 1 and 4; `slider-crank-component` steps 1 and 2. Steps
    now framed on their focus: `horizontal-reduction` step 4, `planetary` step 4, `slider-crank` steps 2 and 3,
    `slider-crank-component` steps 3 and 4. The checked-in images under `docs/assets` keep the commits their
    receipts name. Check reports do not change (the golden files are byte-identical).
  - The solid pane of an explainer beat (`marty-solid render` on `"kind": "explainer"`) is framed by the same rule, from
    the step the beat shows; the pane is the whole safe window (its title and caption sit outside it).
  - `marty-solid render` (assemblies and explainers with a solid) also writes `loop.mp4` (H.264 through AVFoundation,
    at the still size, every rendered loop frame at its exact time, no frame reordering; a failed, cancelled or stalled
    encoder stops the render and removes its directory) and records it in the manifest (`codec`, `width`, `height`, `frames`, `fps`,
    `loopSeconds`, `framingScale`). `--loop-fps 30` renders 360 frames over the same 12 s for the MP4; the GIF keeps
    every third frame (the poses of the 10 fps loop). `MGSolidRenderPlan` gains `loopRate`, `loopRates`,
    `gifFrameIndices`, `bands`, `cameras` and `MGSolidShot.step(_:_:)`; each still's manifest record gains `framing`
    (`focus`, `model`, `modelFitted`).
  - New built-in components: `mannequin` (a smooth schematic adult figure, 1.75 m, facing −Y; shoulders and elbows
    are revolute joints held at the `leftShoulder`, `rightShoulder`, `leftElbow`, `rightElbow` angles; anchors
    `back`, `head`, `leftShoulder`, `rightShoulder`, `leftHand`, `rightHand`, `leftFoot`, `rightFoot`; 12 parts,
    26,048 triangles) and `centrifugalCompressor` (an impeller with `vanes` backswept vanes and as many splitters
    on a disc, inside a ring of `diffuserVanes` wedge vanes; `diameter`, `bore` and the check `bore`; 28 parts and
    5,996 triangles at the defaults). The catalog lists 9 components (about 5.6 KB). See
    [docs/SOLID-3D.md](docs/SOLID-3D.md#figure-and-compressor-components).
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
  - Fourth-check fixes (PR #32): when one call presents several beats (`finishNow`, `.immediate`), only the shown
    beat's line is due; the speech wait applies to every 2D engine placeholder, also in an `unchecked` line.
  - Fifth-check fixes (PR #32): host `apply` and learner changes keep the pose rule for 3D dimension facts in board
    text (one transaction; `text.pose.board`); a new header in the same call drops the old explainer's due lines.
  - The board view draws its transitions on `MGSceneController.presentationClock` when set (default nil: the wall
    clock, as before). `MGLessonController` and `MGExplainerController` set their session's monotonic clock, so a
    wall-clock jump cannot show an earlier frame while the session says the board has settled.
  - 3D annotations (PR 3a, merged before this PR) inside explainers: annotation ids join the one namespace,
    annotation claims and the solid's legend notes join the one legend, beat views take `annotate`
    (`view.annotate…`), the check report carries the assembly's `annotations`, and hosts draw annotations only
    through `checkedAnnotations` (`MGSolidRenderer(document:)`, `show(document:view:)`, the frame overlay). A
    caption, the title or board text may show a `dim.<id>` fact only when it holds at every pose of its views
    (`text.pose.beat.<n>`, `text.pose.title`, `text.pose.board`).
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
