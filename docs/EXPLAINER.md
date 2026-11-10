# Explainer documents (2D, 3D or both)

An explainer is one document that answers one question with a 2D board (a v1 scene), a 3D solid (an assembly v2), or
both. ONE list of beats drives both views, ONE id namespace covers 2D items and 3D parts, and ONE legend counts every
claim. The board, lesson and assembly formats do not change meaning; an explainer only combines them.

Status: preview (unreleased, wire `v: 1` of the explainer format). Examples: [`Examples/Explainers`](../Examples/Explainers/README.md).

<!-- card:start -->
### Choose 2D, 3D or both

Write one explainer document: `{"v":1,"kind":"explainer",…}`. Pick the form per question.

| The answer is mainly… | Use | Key |
| --- | --- | --- |
| a table, chart, graph, step list or formula | 2D | `board` |
| a machine, a shape in space, a mechanism | 3D | `solid` |
| a 3D thing plus its numbers or a comparison | both | `board` and `solid` |

Rules:
1. Beats drive both views. 2D changes add up. The 3D `view` is set fresh in each beat.
2. One id namespace for 2D items and 3D parts. `t.r2` is row 2 of table `t`.
3. No typed digits in `say` or 2D text. Show numbers with `{name}` (2D values) or `{part.fact}` (3D facts).
   Typed data needs a note: `"notes":{"t":{"basis":"where it is from"}}`.
4. Run `marty-solid check --strict FILE.json`. Fix the first `reason`. Check again.

2D only:
```json
{"v":1,"kind":"explainer","title":"Inner planets by width","notes":{"t":{"basis":"NASA fact sheet"}},
 "board":{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"header":true,
  "cells":[["Planet","km"],["Mercury",4879],["Venus",12104],["Earth",12756],["Mars",6792]]}]},
 "beats":[{"say":"Venus and Earth are almost the same width.","highlight":["t.r2","t.r3"]}]}
```

3D only:
```json
{"v":1,"kind":"explainer","title":"A small gear turns a big gear",
 "solid":{"v":2,"parts":[
  {"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},
  {"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}],
  "constraints":[{"gearMesh":{"a":"p","b":"w"}}]},
 "beats":[{"say":"The small gear has {p.teeth} teeth; the big gear has {w.teeth}.","highlight":["p","w"]},
  {"say":"The big gear turns {w.speed|abs|frac} of a turn, the other way.",
   "check":[{"value":"w.speed","lt":0}],"highlight":["w"],"view":{"spin":1}}]}
```

Both (the same gears, plus a table of their facts):
```json
{"v":1,"kind":"explainer","title":"Tooth counts set the speed",
 "board":{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"header":true,
  "cells":[["gear","teeth","turns"],["small","{p.teeth}","{p.speed}"],["big","{w.teeth}","{w.speed}"]]}]},
 "solid":{"v":2,"parts":[
  {"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},
  {"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}],
  "constraints":[{"gearMesh":{"a":"p","b":"w"}}]},
 "beats":[{"say":"Count the teeth: {p.teeth} and {w.teeth}.","highlight":["t.r1","t.r2","p","w"]},
  {"say":"So the big gear turns {w.speed|abs|frac} of a turn.","check":[{"value":"w.speed","lt":0}],
   "highlight":["t.r2","w"],"view":{"spin":1}}]}
```
<!-- card:end -->

The section above is the authoring card. A test keeps it at most 3,072 bytes, parses each JSON block, checks that it
equals the example file and runs it with `--strict`.

Expected results (test X1): the 2D example shows "Venus and Earth are almost the same width." and the legend
"Given 1" (the table is data as given; the caption shows no engine number, so it has no tier). The 3D example shows
"The small gear has 15 teeth; the big gear has 30." and "The big gear turns 1/2 of a turn, the other way." with the
legend "Solved 5" (2 motion claims, 2 captions, 1 check). The mixed example fills the table cells "15", "1", "30" and
"-0.5", shows "Count the teeth: 15 and 30." and "So the big gear turns 1/2 of a turn." and its legend is "Solved 6"
(2 motion claims, the table, 2 captions, 1 check).

![Beat 1 of the mixed example: the table rows and both gears highlighted together](assets/explainer/gears-mixed-beat-1.png)

## Document

```json
{"v": 1, "kind": "explainer", "title": "…", "primary": "solid",
 "notes": {"t": {"basis": "NASA fact sheet"}},
 "board": { …v1 scene… },
 "solid": { …assembly v2… },
 "beats": [ {"say": "…", "unchecked"?: "…", "ops"?: […], "check"?: […], "highlight"?: […], "view"?: {…}} ]}
```

| Key | Required | Rule | Refusal |
| --- | --- | --- | --- |
| `v` | yes | 1 (the explainer format version) | `explainer.version` |
| `kind` | yes | `"explainer"` | `explainer.kind` |
| `title` | no | plain text; 1–80 characters after 3D facts fill it; placeholders name 3D facts only; typed digits make the title Described | `explainer.title` |
| `primary` | no | `"board"` or `"solid"`: the larger pane. Default: `solid` when there is one. It must name a present view. | `explainer.primary` |
| `notes` | no | 1–24 entries; key = a 2D item id; value = exactly one of `{"basis": "…"}` or `{"unchecked": "…"}`, 1–60 characters | `notes.object`, `notes.count`, `notes.entry.<id>`, `notes.text.<id>` |
| `names` | no | 1–24 declared names (rule N1, "Declared names" in [SOLID-3D.md](SOLID-3D.md#placeholders)): each one token of 1–24 characters that starts with a letter and holds a number character, not a number or a quantity ("2e3", "120N", "Mach2", "USD120"). A caption, 2D text (`add`, `set`, board cells, bar labels, control labels, template params) or solid text token that exactly equals one is not a typed number. The solid compiles with them added to its own `names`. | `names.count`, `names.text.<n>`, `names.token.<n>`, `names.number.<n>` |
| `board` | one of the two | a v1 scene without `steps`, `title` or `"dim": "3d"` | `explainer.board`, `explainer.board.steps`, `explainer.board.title`, `explainer.board.dim`, inner scene reasons |
| `solid` | one of the two | an assembly `"v": 2` without `steps` or `title`; `kind` may be left out | `explainer.solid`, `explainer.solid.version`, `explainer.solid.steps`, `explainer.solid.title`, inner assembly reasons |
| `beats` | yes | 1–16 beats | `explainer.beats`, `explainer.beats.count` |

Other refusals: `explainer.json` (not UTF-8 JSON text), `explainer.object`, `explainer.unknown.<keys>` (sorted
author segments), `explainer.empty` (neither view), `explainer.bytes`, `explainer.depth`, `explainer.number` (NaN or
an infinity in a value built in code). A key named `tier` anywhere is `tier.key`, inside `board` too.

Beat keys:

| Key | Rule | Refusal |
| --- | --- | --- |
| `say` | 1–200 characters; placeholders as below; rule N1 | `beat.missing`, `stmt.say`, `text.number.beat.<n>` |
| `unchecked` | 1–60 characters; the caption may type numbers and is Described ("Not checked") | `beat.unchecked.<n>` |
| `ops` | 0–12 lesson commands (`add`, `set`, `remove`, `params`, `camera`, `animate`, `bind`, `unbind`); needs `board` | lesson reasons, `explainer.op.title`, `explainer.board.missing`, `beat.ops`, `beat.ops.count` |
| `check` | 0–8 checks `{"value", "eq" \| "lt" \| "gt", "tol"?}`. A plain name is a 2D value (lesson semantics); a dotted name is a 3D fact (#21 semantics) | `beat.check`, `beat.checks.count`, lesson reasons (`check.<name>`, `check.unknown.<name>`), `check.fact.<name>`, `check.failed.<name>` |
| `highlight` | 1–16 ids of the namespace or table sub-addresses; presentation only | `beat.highlight`, `beat.highlight.count`, `beat.highlight.ref.<id>` |
| `view` | the 3D view of the beat: `focus`, `explode`, `camera`, `orbit`, `spin`, `section`, `ghost`, `annotate`, `pose`, `hide`, `show` (step rules, docs/SOLID-3D.md "Step pose and step visibility"); needs `solid` | `view.object`, `view.unknown.<keys>`, step reasons renamed `step.` → `view.` (`view.section.parts`, `view.camera`, `view.pose`, `view.pose.ref`, `view.pose.key`, `view.pose.with`, `view.pose.solved`, `view.hide`, `view.show`, `view.hide.both`, `view.hide.use`, `view.hide.claim`, `view.hide.fact`, `view.show.claim`, `view.pose.fact`), `ref.unknown.<id>`, `section.*`, `assembly.budget`, `explainer.solid.missing` |

Beat numbers in reasons are 1-based (`text.number.beat.2` is the second beat). `MGExplainerIssue.beat` is 0-based.
A 3D check's shape reasons use the lesson names: `step.check.unknown.<keys>` of an assembly is `check.unknown.<keys>`
in an explainer.

## One beat timeline

```
 explainer
   ├─ board + beats[].say/ops/check (plain names) ──► MGLessonSession: 2D state, pacing, lines, events
   ├─ solid                                       ──► MGSolidDocument, compiled with every kept beat's view as a step
   ├─ beats[].check (dotted names)                ──► MGSolidClaimCheck against the 3D facts
   └─ beats[].highlight                           ──► 2D emphasis, table rows and cells, 3D part highlight
                          │
                          ▼
 MGExplainerSession: one beat cursor, one caption, one legend, one event history
```

1. One cursor. `MGExplainerSession` wraps one `MGLessonSession`; the lesson owns pacing, lines, pause and resume.
2. A 3D-only explainer runs the lesson on an empty board built in code (no wire statement can make one). Commands are
   refused there (`explainer.board.missing`), and there is no `boardPresented`.
3. 2D changes add up (lesson rule). The 3D view is set fresh in each beat: a beat without `view` shows the default view.
   A view's `pose` moves parts for that beat only, and its `hide` and `show` hide parts or show a show-only part for that
   beat only (docs/SOLID-3D.md, "Step pose and step visibility"). A part the beat's view hides makes no claim in the beat:
   the beat's caption, its 3D checks and the text of the annotations it shows may not show one of its facts, and the
   title and the board text (which show with every view) may not show a fact of a part that any view hides
   (`view.hide.fact`, `id` names the fact). Every 3D check of a beat, and every 3D fact a posed beat displays (caption,
   title, board text, annotation text), must hold over the beat's whole motion domain at its pose (every input its
   `spin` plays, at its explode value and placements; the rule shown dimensions follow): a `dim.<id>` fact that does
   not provably hold is `view.pose.fact`. Host edits and restore name the fact in `id` too. This holds for a view streamed later that changes a pose, and on restore. When some view hides
   parts, the legend counts the motion of a part only once a presented beat displayed it (the snapshot's `shownMotion`,
   checked on restore like `shownAnnotations`); when no view hides any part, all motion counts, as before. In `story.mp4` the camera move
   into a beat also moves the posed parts from the previous beat's pose; the hold shows the beat's own pose. Snapshot and
   restore keep each beat's view as written, so a restored session recompiles the same poses.
4. Highlight is presentation: it changes no state and is never a claim. At presentation every id is resolved again; an
   id that no longer resolves is dropped and recorded in `hostIssues` (`beat.highlight.stale.<id>`).
5. A beat settles when its 2D transition settles and its 3D `spin` has played (4 s per input turn,
   `MGExplainerLimits.spinSecondsPerTurn`). `.immediate` pacing skips motion in both views.
6. A failing check, 2D or 3D, refuses the whole beat: the 2D state goes back to the beat's start, the beat's view,
   highlight and 3D checks are dropped (a dropped view releases its cut budget), and its later statements are
   cascades (`beat.refused`). A refused `view`, `highlight` or command is refused alone; the beat keeps the rest.
7. A refused statement changes nothing: 2D state, 3D views, cut cache, budget counters, legend, timers. A refused
   beat leaves no claim: an item that only a refused beat added or changed is not counted (see "What the legend
   counts").
8. A beat's `view.section` is cut when its statement is accepted. The cut counts toward the document's mesh budget
   (`assembly.budget`) and section work budget (`section.budget`) with every other kept view.
9. A claim holds at every state its beat can show. After a learner change (a slider) or a host `apply`, `caption` is
   the presented beat's line filled again from the state shown now (live engine values, never a stale number), and a
   2D check of the presented beat that no longer holds is not current (`notCurrent`): it leaves `claims` and the
   legend until the state makes it true again. It is never kept as "Checked" on a false state.
10. A number-bearing caption and its checks show only when the board shows the state they describe. While the board
    still moves to it (the beat's `animate` keyframes play, or a blend changes drawn items; `boardSettled`,
    `motionRemaining`), the caption shows each 2D number as "…", and the caption claim and the beat's 2D checks are
    pending (`pendingClaims`): out of `claims` and the legend. They appear when the motion has played; paused time
    does not count, and `nextWake` wakes the host then. `.immediate` pacing and `finishNow()` play no motion: the board
    gets the end state as a direct change in the same step (`finishNow` publishes a new direct change if a motion was
    still playing), so state and text match at once. 3D facts are rates per input turn, tooth counts, travel over a
    full turn and dimension facts (`dim.<id>`). The first three hold at every pose. A dimension fact is measured at
    one pose, so the assembly's rule for shown text applies unchanged: a caption, the title or board text may show
    `dim.<id>` only when that dimension holds at every pose its view can show (`text.pose.beat.<n>`,
    `text.pose.title`, `text.pose.board`; `MGSolidAnnotationEngine.dimensionHolds`). Host `apply` batches and learner
    changes pass the same rule as one transaction, on each command and on the resulting board; a refused change keeps
    the board, the claims and the motion. Every shown 3D number therefore
    holds at every pose of a `spin`, and the host shows a view's first pose at once (`show(document:view:)` poses the
    parts and attaches the annotations in one transaction), so no 3D number has to wait.
11. Speech is learner-visible. A beat's `lineDue` (the line a host speaks) never carries a 2D engine number before
    the board shows the state it describes: when such a line is due while the board still moves, `lineDue` waits and
    fires when the motion settles, filled from the state shown then (the simpler of the two options; there is no
    number-free first version). A line without a 2D engine number fires as before. With `.estimate` pacing the
    line's time starts when it is due; a line the host ends before it is due is dropped, never spoken late;
    `finishNow()` makes a waiting line due at once. The wait applies to every 2D engine placeholder in a line,
    whatever the beat's word tier (an `unchecked` line that shows `{theta}` waits too). A host adopts the board once
    per call, so when one call presents several beats (`finishNow()`, `.immediate` over a whole document or one large
    chunk), only the line of the last beat, the one the board then shows, is due; the skipped beats' lines are not
    returned (the history keeps them, and the report keeps their captions). The same holds across documents: when a
    header in the same call starts a new explainer, the earlier explainer's due lines are not returned. `lineQueued`
    is for prefetch only: do not speak it.

## Adaptive board pane

An explainer with both a board and a solid does not give the board half of every frame. The rule is
`MGExplainerSession.boardPane` (`MGExplainerBoardPane.rule`), and the renderer stills, `story.mp4` and the SwiftUI
explainer view all read it:

1. The rule reads the presented 2D state (`state`): the state that each presented beat, set-up command and accepted host
   or learner change makes the shown state. It is the newest state in the legend's record of presented items
   ([What the legend counts](#what-the-legend-counts-presented-only)), so the pane never decides on an item the legend
   does not count.
2. The board pane is drawn while that state has at least one item that is not a `text` item: a table with a data row,
   a plot, a body, a vector, a region, a highlight, any other kind. An empty table does not count (see
   [Empty tables](#empty-tables)).
3. While it has only `text` items and empty tables (or none), the solid takes the whole frame. The board's texts are not lost: they
   move, in board order and joined with " · ", to the title band (`boardPane.line`; in a still and in `story.mp4` a
   line under the legend line, truncated with an ellipsis to the width; in the SwiftUI view a line under the title).
4. An explainer with only a board always draws it; an explainer with only a solid has no board pane.
5. The rule is deterministic: the same document gives the same pane in every beat on every host. A highlight of a
   2D text item has nothing to draw on while the pane is hidden.

### Empty tables

A table with no data row is not drawn, and it does not open the board pane (`MGItem.isEmptyTable`). A data row is a row
after the header row (every row when the table has no `header`); a table is empty when every cell of its data rows is
empty or only white space. So a header-only table that a later beat fills with `set` (`{"op": "set", "id": "t",
"key": "cells", ...}`) shows nothing on the beats before that fill: in an explainer with a solid, the solid takes the
whole frame there, and the beat that fills the table opens the pane. That change of layout is the board pane opening,
which the story slides open with the camera move into the beat ([Pane slide in the story video](#pane-slide-in-the-story-video))
and the SwiftUI view animates; it is not a cut. The other choice, keeping the pane open as an empty space, was not
taken: it shows a blank half frame on every beat before the fill and makes the solid smaller there for nothing. An
explainer with only a board keeps its pane, with no table drawn in it. The same rule holds in a plain lesson: the 2D
renderer (`MGCanvasRenderer`) draws no table without a data row. The board pane width (`boardShare`) measures no empty
table.

### Board pane width

Side by side (a frame wider than tall), the board pane is as wide as its content needs, not a fixed 45 %
(`MGExplainerFrame.boardShare`). The shown board's items are measured at the viewport of the reference pane (the board
pane at its largest share, `boardReferenceSize`); the share is the width they span about the pane centre plus 24 px
(`boardMargin`, scaled with the width) on each side, over the split width, bounded to 28 % (`boardMinShare`) ... 50 %
(`boardMaxShare`), or 55 % (`boardPrimaryMaxShare`) when the board is the primary view. A board with nothing
measurable keeps the largest share. The board is drawn at the reference pane's scale and centre, so a narrower pane
crops only empty board. The rule is deterministic and the same in the stills, `story.mp4` and the SwiftUI explainer
view (which passes its own area in points). Stacked layouts (taller than wide) keep the 55 % / 45 % split. A 4-row
table gets about 28 % at 1280 × 800. Each split beat's manifest record gives `boardShare`. A beat whose share differs
from the previous beat's changes the solid pane, so the story slides the panes there
([Pane slide in the story video](#pane-slide-in-the-story-video)).

### Pane slide in the story video

When the pane layout changes between two beats (the board pane opens, closes or changes width), `story.mp4` does not
cut. The panes slide during the camera move into the beat (`MGPaneSlide`):

1. **Panes.** At share `s` of the move (the move's eased camera blend, 0...1) every pane edge lies `s` of the way
   between its two layouts, rounded to whole pixels. The solid pane eases from full frame to its split rect, or the
   reverse. A board pane that opens grows from zero size at its outer edge (the left edge side by side, the top edge
   stacked); one that closes shrinks to that edge.
2. **Camera.** The camera moves as any move does: straight, or along a routed path ([SOLID-3D.md](SOLID-3D.md#routed-moves))
   tested against the parts' swept boxes, and it cuts only when no path is clear (`path` `cut`, `pathReason`
   `blocked`; the panes then jump too). The move's key cameras are each fitted to their own beat's pane, and the
   camera blends between them with the same share as the panes. On every frame the camera is fitted to the current
   solid pane (`MGPaneSlide.camera`): the 3D image is rendered at the pane's current pixels, and when the pane is
   narrower than the blended aspect (pixel rounding, or a stacked layout) the field of view widens by that ratio. The
   camera position is never changed, so the routed path stays as tested.
3. **Board.** The board fades in or out in its sliding pane, drawn at its own size and centred in the pane (the pane
   crops it). As in every move, the board shows the previous beat's state until the hold starts: a closing pane fades
   out the previous beat's board; an opening pane fades in the previous beat's board state drawn for the new pane,
   while the board line it replaces fades out of the title band. The new beat's board, caption, labels and board
   claims appear on the first frame of its hold. No label is drawn during the move.
4. **Holds.** At share 0 the panes are exactly the previous beat's and at share 1 exactly this beat's. In every hold
   frame the layout, the camera, the board state, the caption and the labels are the beat's still's. Parts that the
   beat's `spin` animates may still move during the hold (the spin plays from the beat's first frame); the beat's
   settled last frame shows the still's pose too.
5. **Length.** The slide takes the move's time: 0.6 s, or 1.0 s for a routed move (`MGStoryTiming`), at most half the
   beat. Deterministic.

The manifest record of each such beat gains `layout`: `{"path": "slide" | "cut", "change": "open" | "close" |
"resize", "seconds"}` (`seconds` 0 for a cut). Its `path` and `pathReason` give the camera's path, as for any beat.

**Story and SwiftUI.** Both read the same pane rule and pane width (`MGExplainerFrame.panes`, `boardShare`), so they
reach the same layouts. They animate the change differently. The SwiftUI view is live: the board pane slides in from
the leading (or top) edge and fades over 0.35 s (`paneAnimationSeconds`), eased in and out, and the solid pane refits
its camera each time its size changes (with Reduce Motion the pane appears and goes at once). The story video is a
recording: the slide runs with the beat's camera move (0.6 s or 1.0 s, smoothstep), so the pane edge and the camera
arrive together, and each hold frame has its still's layout, camera, board state, caption and labels (a spinning part
may still move until the spin ends). The story does not copy the 0.35 s timing.

In `marty-solid render` the pane rects are whole pixels (`MGExplainerFrame.panes`), and the solid pane is framed for
exactly the pixels it is rendered at (`MGExplainerFrame.solidCamera`), so a beat's still and the hold frames of that beat
in `story.mp4` have the same camera in either layout. The unblocked-focus rule applies to the pane
([SOLID-3D.md](SOLID-3D.md#unblocked-focus)): a beat framed on its focus draws parts that hide it as automatic ghosts, or
looks from another fixed direction. Each beat's manifest record gives `camera`, the unblocked-focus fields (`autoGhost`,
`occluded`, `focusSamples`, `view`, `facesCut`) for a tested focus, and `offView` (anchors outside the pane plus focus
samples still hidden) when the beat shows annotations or has a tested focus.

In the SwiftUI view the board pane slides in and out over 0.35 s
(`MartyGraphicsExplainerView.paneAnimationSeconds`); with Reduce Motion it appears and disappears at once. A board
that is never drawn records no first board frame (`boardFrame` stays nil).

### The solid pane in SwiftUI

The SwiftUI solid pane (`MGExplainerController`, shown by `MartyGraphicsExplainerView`) frames each beat with the
function that frames the beat's still and its hold frames in `story.mp4`:
`MGExplainerFrame.solidClearView(_:view:stepIndex:aspect:)`, for the step the beat shows
(`MGExplainerSession.solidStep(forBeat:)`), at the beat's end pose and at the pane's aspect in points (the framing reads
only the aspect; the `pane:` form reads `MGFrameRect.aspect`). The pane has no title or caption over it, as in a still,
so the whole pane is the safe window. So the pane gets the per-step focus framing, the unblocked-focus rule (automatic
ghosts drawn at 0.2, or an alternate direction) and every camera preset, `backLeft` and `backRight` included. It draws
the beat's view with the same automatic ghosts. The controller publishes the result (`paneClear`, `paneView`); it
computes no camera of its own. For the same beat and the same pane aspect, the pane camera is the still's camera. The
"shown parts stay whole" rule ([SOLID-3D.md](SOLID-3D.md#rendering-camera-framing-and-the-loop)) is part of that one
function, so a beat's still, its story hold frames and the pane never cut a solid part, except an explicit `focus`
close-up that the check report warns about (`framing.cut.beat.<n>`).

- **Start pose and the learner's camera.** The framed camera is the start pose of each beat. In a solid without
  annotations the learner may orbit and zoom (SceneKit camera control). Each new framing increases
  `MGExplainerController.cameraReset`: a new beat, a recompiled solid, or a new pane aspect. The view then builds a
  fresh scene view on the framed camera, so the learner's orbit, any camera SceneKit switched to, and its orbit pivot
  are dropped. A layout pass with the same size does not reframe. With annotations the learner cannot move the camera,
  so the overlay always matches the picture.
- **Timing.** The pane cuts to the next beat's framed camera, as it did before. It plays no camera move and adds no
  timing rule. The story video plays its routed camera moves (and cuts a blocked move); the live pane does not copy
  them. When the board pane slides (0.35 s), the solid pane frames once for its new size.

## One id namespace

One namespace holds 2D item ids (after template build and `hide`, and every id an `add` op introduces), 2D control
ids, and 3D part ids, `repeat` copy ids, `repeat` base ids, component instance ids and anchor names. Ids are
case-sensitive. Collisions are refused with `explainer.id.duplicate.<id>`:

* when the second of `board` and `solid` arrives: each id of the arriving view, in its canonical order (2D: resolved
  item order; 3D: for each resolved part its instance ids, its `repeat` base and its own id, then anchor names sorted),
  is checked against the other view; the first collision refuses the statement;
* when a command introduces a 2D id (any command, also a `params` change that builds new template items) or a control
  (`bind`): against the 3D ids and the controls. Controls join the namespace here; in a plain lesson they have their own.

A 2D command that names a 3D id (`set`, `remove`) is `explainer.id.view.<id>`; a note that names a 3D id is
`notes.view.<id>`. A table sub-address is valid in `highlight` only: `<table>.r<k>` (row `k`, 0-based, the header is
row 0) and `<table>.r<k>c<j>` (one cell), decimal without a sign or a leading zero, inside the table's size at that beat.

3D annotations (open-vocabulary PR 3a) work inside an explainer exactly as in an assembly v2: the solid's
`annotations` (labels, arrows, dimensions) and each beat view's `annotate` (`view.annotate`, `view.annotate.count`,
`view.annotate.ref.<id>`) follow the assembly rules, including visibility, the linear-motion rule and the pose rules,
because every beat view compiles as a solid step. One difference, the visibility limit: in an explainer the limit of
12 applies to each beat's own `view.annotate` list. With more than 12 annotations (up to the solid's caps: 32 labels,
32 arrows, 16 dimensions), the solid is stepped from its statement on: the views before the first beat and every beat
without an `annotate` list show none, and each beat shows exactly its list. A beat that lists more than 12 is
`view.annotate.count`; the report's `visibility` gives `{"annotation" (the 13th id of the list), "cause": "beat",
"beat" (1-based), "count", "limit"}`, with `location.beat` (0-based), `location.id` and `location.detail`. With 12 or
fewer annotations the assembly rule stays as before (no `annotate` anywhere: every beat shows all of them), so such
documents do not change. `annotations.visible` therefore never refuses an explainer. Annotation ids join this namespace after the anchor names, in
authored order (a 2D id equal to one is `explainer.id.duplicate.<id>`). A beat may highlight an annotation id (drawn
bright). Annotation claims join the one legend after the motion claims, and the solid's legend notes ("Arrow lengths
are not to scale") join its notes. Hosts draw annotations only through the assembly's one gate
(`MGSolidDocument.checkedAnnotations`): the renderer is loaded from the compiled solid (`MGSolidRenderer(document:)`,
`setDocument(_:)` after each recompile) and shows each beat with `show(document:view:)`; the SwiftUI pane and
`marty-solid render` lay out labels with `MGSolidAnnotations.frame` at the pose shown, and the pane keeps the engine's
camera when the solid has annotations, so the overlay matches the picture. Compiled documents and views stay
read-only.

## Numbers, tiers and the legend

The dot rule: a placeholder name **without** a dot is a 2D engine value (`MGScene.values`); a name **with** a dot is a
3D fact (`MGSolidDocument.fact`). There is no lookup order.

| Text | Names | Modifiers | Filled from |
| --- | --- | --- | --- |
| beat `say` | plain and dotted | #21 set on 3D facts; `abs` needs a check of the same beat that proves the sign (`text.sign.<name>`); a plain name takes none (`text.modifier.<mod>.<name>`) | the presented 2D state and the 3D facts |
| 2D item text, table string cells, node text | plain and dotted | #21 set on 3D facts; `abs` is refused (`text.sign.<name>`) | 3D facts, at each board parse and patch |
| `title` | dotted only | #21 set; `abs` refused | 3D facts, when the views are fixed (the first beat) |

Inside an explainer the text limit applies to the filled text; the raw text may be up to four times the limit (a table
cell `"{p.teeth}"` must fill to at most 12 characters, else `table.cell`). 3D facts use the #21 formatter, which never
shows a non-zero value as "0" (`text.rounding.<name>`); 2D values keep `MGValue.text`.

Rule N1 (owner decision D2): every number character the learner sees in author text comes from a placeholder. Every
Unicode scalar counts (the #21 number test). It applies to beat captions (except with `unchecked`:
`text.number.beat.<n>`), and to 2D item text, table and array cells, bar values, plot ranges, `over` values and the
strings of `set` and `add` commands, unless the item has a note (`text.number.item.<id>`). N1 and the declared names
read text in Unicode NFKC form, so full-width "２" and every other number form count ("Which characters are numbers" in
[SOLID-3D.md](SOLID-3D.md#placeholders)). A token whose NFKC form exactly equals a declared name (the header's `names`,
see below; kept in NFKC form, so "Ｍａｃｈ２" is refused as "Mach2") is not a typed number; nothing else is exempt. The token rule and the
name rules are the ones in [SOLID-3D.md](SOLID-3D.md#placeholders), "Declared names". A control label may not
type a number (`text.number.control.<id>`); a raw template's params may not carry a string with one
(`text.number.template`). Inside an explainer the lesson's decimal rule (`text.literal`) is off: N1 replaces it.

| Source | Tier | Chip |
| --- | --- | --- |
| A template value (`board.template`) | Solved; Built when the template marks a value as data (`MGTemplateBuild.builtValues`) | "Solved" / "Data as given" |
| A 2D item with a `basis` note | Built | "Data as given" |
| A 2D item with an `unchecked` note | Described | "Not checked" |
| A 2D item whose numbers all come from placeholders | the lowest tier of its placeholders | as captions |
| A 2D item with no numbers and no note (shapes, plot points, regions) | no claim | "Shapes and drawings as authored" |
| A caption | Described with `unchecked`; else the lowest tier of its placeholders; none without a placeholder | "Numbers solved", "Schematic", "Not checked" |
| A check | the tier of its value | "Checked" |
| 3D motion | the #21 motion tier | as in the assembly |

`MGExplainerSession.claims` lists the claims in this order: 3D motion (part order), 3D annotations (authored order), the title,
`board.template`, 2D items `item.<id>` (first-shown order, below), then per presented kept beat `beat.<n>` and its checks
`beat.<n>.check.<k>`. The one legend (`MGExplainerLegend`, owner D4) shows `Solved N · Schematic N · Given N · Not
checked N` (each group only when non-zero). `Schematic` counts Built claims of every kind except `data`; `Given`
counts Built `data` claims (noted 2D items), so a 3D-only explainer has its assembly's own legend text (test T9).
Notes: "Some motion is schematic" when a motion claim is below Solved; "Shapes and drawings as authored", always.

### What the legend counts (presented-only)

The legend counts the claims of exactly what the learner was shown, from the states that were actually presented. A
state is presented when it becomes the shown state (`state`): the board's scene statement, each set-up command, each
presented beat (as presented, so a command that is refused alone at presentation changes nothing), and each accepted
host `apply` or learner change. The lesson hands every such state to the explainer as it is shown (also when one call
presents several beats), and the explainer freezes the claims of its 2D items at that moment (internal
`MGShownItems`): each item id in first-shown order, with the set of tiers its displayed numbers had. The displayed
content is the effective one: the item's wire entry with the scene's `over` entries for it applied in order, so an
override that a later one supersedes was never displayed and does not count. Each placeholder takes the tier of that
state (a 2D value is Built when that state's template marks it as data, else Solved; a 3D fact has its own tier).
Nothing is recomputed later. The record only grows: at most 1024 ids (the lesson's id history cap) with at most 3
tiers each.

1. A 2D item claim counts for every item in the record, also when a later beat or host change removes it (a noted
   table that beat 1 adds and beat 2 removes counts as `Given 1`). Its tier is the lowest tier it showed, as frozen
   then: a later change of the board (a template that no longer marks the value as data, a value that is gone) does
   not change it.
2. A caption claim and the check claims of a beat count once the beat is presented (and, as before, while the board
   still moves to it they wait: `pendingClaims`). The presented (current) beat's caption and checks are live: their
   tiers follow the state shown now, and a 2D check that the state shown now breaks leaves the legend (`notCurrent`).
   A past beat's are frozen (internal `MGShownBeats`): on its presentation and on every state shown while it was the
   presented beat (host or learner changes), the engine records the tier its caption had and the tier each check's
   value had, with that state's built values. A past beat's caption and checks take the lowest frozen tier ("Checked"
   with that tier) and are never recomputed from a later board.
3. A 3D annotation claim counts only for what a presented beat draws: its step's annotations less the arrows the beat
   drops (`MGExplainerSession.displayedAnnotations`; one drop set per beat, the one its still, story frames and the
   SwiftUI pane use, [SOLID-3D.md](SOLID-3D.md#arrow-drop)). A dropped arrow is not presented in that beat. Under the
   show-all rule an arrow that every kept beat drops makes no claim.
4. Nothing else counts: not a beat that waits to be shown (queued), not a beat that is still open while it streams,
   not a paused lesson's next beat, not a refused beat, command or batch, not the middle of one beat's commands, not a
   note whose item never appears (`notes.unused.<id>`), and no replay of the script. `finishNow()` presents the
   waiting beats, so they count after it runs.

The title and `board.template` count when they are shown (the title from the first beat on, the template with the
board). 3D motion claims come from the whole compiled solid; they do not depend on the beat shown. Annotation claims
follow what is displayed. With the show-all rule (no beat has an `annotate` list and the solid has at most 12
annotations) every view displays every annotation, so all of them count. Whenever the beats choose their labels (some
beat has `view.annotate`, at any count, or the solid has more than 12), an annotation claim counts only once a presented
beat has displayed it, at its tier at presentation, and it keeps counting after later beats. A beat with
`"annotate": []`, or without a list, displays none and adds none. One function gives a beat's displayed list to both the
overlay and the legend (`MGSolidDocument.visibleAnnotations` for the beat's step, `displayedAnnotations(beat:)`), so in a
live session the counted set is the set the learner was shown. `load` of a whole document in which some beat has
`annotate` makes the solid stepped from its statement on, so every beat displays during the load what it displays in
the loaded document, also after such a beat is refused later; a stream takes the mode when it accepts such a view and
keeps it (also if that beat is refused later), and the labels its earlier beats displayed keep counting. The
label-selection mode is saved state: the snapshot's `chooseLabels` is `true` or absent (any other value, `false`
included, is `snapshot.labels`). `true` is used as saved. Absent (an older snapshot, or no list so far), restore derives
the mode from every beat the snapshot knows (kept, refused or queued) and keeps it for the rest of the session. The
record is
`MGShownAnnotations`, the snapshot's `shownAnnotations` (written whenever the beats choose their labels, at any
annotation count: at most 80 entries `{"id", "tier"}`, at most 8,976 bytes). After a restore the record is saved data
checked for structure, not proof of what was shown (see Persistence): each id once, an annotation of the solid with a
claim, at that claim's tier, and it must hold every annotation the presented beats display now (else
`snapshot.shown`); without the field it is rebuilt from the presented beats. An annotation that no presented beat
displayed makes no claim.
One function (`claims`) serves `legend`, `MGExplainerReport` (`marty-solid check`, which presents every beat),
`snapshot check` and `MartyGraphicsExplainerView`; `marty-solid render` draws the legend of a copy of the session after
`finishNow()` (every beat presented) in each still and in the manifest.

`describe(_:)` routes by member: a 2D id gives the lesson's describe, a table sub-address the table's plus `row` (and
`column`), a 3D part, anchor or `repeat` base the solid's describe, an instance its parts; an unknown id gives nil.

## Statement stream

`MGExplainerSession.feed(_:)` takes raw text; `MGExplainer.statements` flattens a document into the same stream (both
give the same final state, test S1). Fixture: [`explainer-mixed.statements.ndjson`](fixtures/v1/explainer-mixed.statements.ndjson).

| Statement | Form | Rule |
| --- | --- | --- |
| header | `{"explainer": {"v": 1, "title"?, "primary"?, "notes"?, "names"?}}` | Required first statement of a new stream (`explainer.header`). A header in a later stream replaces the explainer. |
| keep | `{"keep": true}` | First statement of a follow-up stream. State, ids, views and controls stay; beat numbers continue. |
| board | `{"board": {…}}` | Once, before the first `say` (`stmt.order`); at most 4 KiB. A board that shows a 3D fact must come after the solid. |
| solid | `{"solid": {…}}` | Once, before the first `say` (`stmt.order`); up to 64 KiB. |
| say | `{"say": "…", "unchecked"?: "…"}` | Starts a beat. The first `say` fixes the views and fills the title. |
| op | `{"op": …}` | A 2D command for the open beat (or set-up before the first `say`). |
| check | `{"check": {…}}` | Plain name: the lesson checks it. Dotted name: the explainer checks it against the 3D facts. |
| view | `{"view": {…}}` | The open beat's 3D view; at most one per beat (`stmt.view.twice`). |
| highlight | `{"highlight": ["…"]}` | At most one per beat (`stmt.highlight.twice`). |
| end | `{"end": true}` | Optional; `endStream()` does the same. |

Anything else is `stmt.kind`. The lesson stream rules apply: a statement is complete at the closing bracket of a
top-level value and is validated at once; a refused statement changes nothing; a beat is presented only when it is
complete; text between statements that is not whitespace is skipped and reported once (`stmt.json`). Every issue names
the explainer's statement index. A document flattens to: header, the board (when it shows no 3D fact), the solid, the
board (when it does), then per beat `say`, commands, checks, `view`, `highlight`, and `end`.

### Events and time to first visible

`MGExplainerEvent`: `accepted`, `refused`, `boardPresented`, `solidCompiled`, `solidPresented`, `lineQueued`,
`lineDue`, `lineStarted`, `lineEnded`, `beatPresented`, `streamEnded`, `explainerComplete`, each with a time from the
injected `MGLessonClock` (`history`).

| # | Measure | From → to | Where |
| --- | --- | --- | --- |
| TE1 | board, core | board statement complete → `boardPresented` | `MGExplainerTiming.boardCore` |
| TE2 | board, frame | request → first Canvas frame of the board | `MGExplainerRunTiming.boardFrame` |
| TE3 | solid, core | solid statement complete → `solidCompiled` | `MGExplainerTiming.solidCore` |
| TE4 | solid, frame | request → first frame of the solid pane | `MGExplainerRunTiming.solidFrame` |
| TE5 | first visible | request → the earlier of TE2 and TE4 | `MGExplainerRunTiming.firstVisible` |
| TE6 | complete | request → `explainerComplete` | `MGExplainerRunTiming.complete` |

`MGExplainerController` (SwiftUI) records TE1–TE6 and writes signposts (subsystem `MartyGraphics`, category
`explainer`: `statement`, `beat`, `solidCompile`). TE4 is the first frame SceneKit renders in the solid pane (a scene
renderer delegate). `MartyGraphicsExplainerView` shows the two panes (the `primary` one larger; side by side when wide,
stacked when tall), the caption, a slider for every bound control and the legend with its notes.

- The board pane is `MartyGraphicsView` on the controller's `MGSceneController`: it plays the lesson's blends and
  keyframes and holds them while paused. It draws its frames on the session's clock
  (`MGSceneController.presentationClock`), so the drawn frame and the session's `motionRemaining` come from one
  monotonic clock: a wall-clock jump can never show an earlier frame while the session says the board has settled. Highlighted items and table rows and cells glow (`emphasis`,
  `tableEmphasis(rows:cells:)`).
- The solid pane plays each beat's `spin` over time from the beat's start (`MGExplainerLimits.spinSecondsPerTurn` per
  input turn; `solidPose(at:)`, `spinProgress(at:)`). `pause()` freezes the pose it shows; `resume()` continues from
  there. `.immediate` pacing and `finishNow()` show the end pose. The camera follows
  [The solid pane in SwiftUI](#the-solid-pane-in-swiftui) below: the beat's still camera, from one function.
- Highlighted 3D parts use the renderer's `.strong` emphasis (`MGSolidRenderer.emphasis`): the 2D emphasis colour as a
  glow, other parts dimmed. The default `.subtle` style of plain assemblies is unchanged. No device budget is claimed: a
physical-device receipt is pending. Authoring advice: write the view the learner needs first, keep the board small,
and put a large solid after a small board.

### Persistence

`snapshot()` holds engine data only: the header, the views as authored (as JSON text), the set-up commands, each
beat's caption template, commands, checks, view and highlight, the lesson snapshot (as JSON text, so its nesting never
adds to the explainer's), the stream position, the record of shown 2D item claims (`shown`:
`[{"id", "tiers"}]` in first-shown order, tiers lowest first) and the record of shown beat claims (`shownBeats`:
`[{"beat", "caption", "checks"}]` by beat, 0-based, each a list of tiers lowest first) and, whenever the beats choose
their labels (some beat has `view.annotate`, at any annotation count, or the solid has more than 12 annotations), the
record of shown annotation claims (`shownAnnotations`: `[{"id", "tier"}]` in first-shown order) and the
label-selection mode (`chooseLabels`: `true` once the session has a beat view with an `annotate` list, after `load` or
in a stream; absent otherwise), and, whenever some view hides parts, the record of shown motion claims (`shownMotion`:
`[{"id", "tier"}]` in first-shown order, at most 96 entries; restore checks it like `shownAnnotations`, and rebuilds it
from the presented beats when it is absent). The mode belongs to one explainer: a new `explainer` header in the same session starts
without it. `chooseLabels` is checked in every snapshot, with or without a solid.
Captions and claims are not stored. `restore(_:pacing:clock:library:)`
and `restore(data:…)` trust nothing in it as proof:

1. the board and the solid are checked and compiled again (the solid with the kept beats' views); every saved check is
   parsed with the authored check rules (a value that is not a check is refused, for example `check.object`), and
   every 3D check is proved again;
2. the script is replayed from the board with the explainer's rules (rule N1, one namespace, every set-up and beat
   command, every 2D check on its beat's end state, every caption), which also gives each beat's caption again;
3. the lesson restores with the explainer's environment; every scene it holds (shown, baseline, each queued beat's
   start and end) passes the board rules (no wire `title` heading, `steps` or 3D dimension), rule N1 and the
   namespace again, and the lesson keeps no title of its own, and every saved control must be one that a checked `bind`
   made (of the replayed script, or a recorded host `bind`; `snapshot.controls`), so a control label is never taken
   from saved data; every queued command passes the explainer's command rules, each queued beat must be the
   explainer's beat, and every kept beat is either shown or queued;
4. every saved presented beat must be a kept beat at or before the lesson's beat that the lesson does not still
   queue (`snapshot.presented`); the record of shown 2D item claims is checked for structure only (`snapshot.shown`):
   an array of at most 1024 entries with closed keys `id` and `tiers`; each id once, an item identifier that the
   restored id history (`kinds`) holds and no 3D id; each tier once, one of `described`, `built`, `solved`; and the
   record holds every item of the state shown now with the tiers that state shows. Past claims are not recomputed
   against the restored board (it may have changed since they were shown). A snapshot without `shown` (made before
   the record) restores with the state shown now as the record. The record of shown beat claims is checked the same
   way (`snapshot.shown`): at most 16 entries with closed keys `beat`, `caption`, `checks`; each beat once and a
   presented kept beat, and every presented kept beat has one; one tier list per check of that beat; each tier once
   and only a tier the beat's text can have (an `unchecked` caption Described, a caption without placeholders none, a
   3D fact its own tier, a 2D value Built or Solved; a caption or check with placeholders at least one); and the
   presented beat's entry holds the tiers it shows now. A snapshot without `shownBeats` freezes each presented beat
   on the state shown now. The record of shown annotation claims is checked for structure too (`snapshot.shown`): at
   most 80 entries with closed keys `id` and `tier`; each id once, an annotation of the solid that has a claim, at
   that claim's compiled tier; and it holds every annotation the presented kept beats display now. The record of
   shown motion claims (`shownMotion`, only while some view hides parts) is checked the same way (`snapshot.shown`):
   at most 96 entries with closed keys `id` and `tier`; each id once, a motion claim of the solid at its compiled
   tier; and it holds the motion of every part the presented kept beats display now; while no view hides parts it
   must be absent, and a snapshot without it rebuilds it from the presented beats. `chooseLabels` must be `true` or
   absent (`snapshot.labels`); `true` is used as saved, and absent derives the mode from every beat the snapshot
   knows. Trust: all four records (`shown`, `shownBeats`, `shownAnnotations`, `shownMotion`) and the flag are saved
   data that pass these structure checks, not proof of what was shown; a changed snapshot can change past item and
   beat claims within them (as it can change the held scenes within the board rules); a forged annotation entry can
   add annotation claims up to the solid's compiled claim tiers, at most 80 entries; a forged motion entry can add the
   motion claim of a part no presented beat displayed, at its compiled tier (a Solved claim for a solved part), at most
   96 entries; and removing `chooseLabels` gives the derived mode, which can show and count at most the compiled
   labels (the show-all rule applies only to at most 12) at their compiled tiers;
5. the caption is the presented beat's line on the restored state, never the saved text; the claims and the legend
   come only from what steps 1–4 evaluated and from the checked records. For an untouched snapshot in the current
   format, a restored legend equals the legend of the saved session; a changed snapshot that still passes the checks
   can change it within the bounds of the trust note (for example, a valid extra `shownAnnotations` or `shownMotion`
   entry adds a claim).

All of it runs in beat order, then statement order, so the first reason does not depend on dictionary order. The first
problem refuses the whole snapshot with its reason (the solid's own reason when it no longer compiles, a rule's own
reason such as `text.number.item.<id>` or `check.<name>`, `snapshot.<field>` otherwise); it is never loaded in part.
`marty-solid snapshot check SNAPSHOT.json` runs the same restore and prints `{"ok", "reason", "location", "legend",
"caption"}`.

## Limits

| Limit | Value | Reason |
| --- | --- | --- |
| Raw document input, read before parsing | 128 KiB | `explainer.bytes` |
| Document (its flattened stream, the solid included) | 64 KiB | `explainer.bytes` |
| Stream, every received byte counted | 64 KiB | `explainer.bytes` |
| Statements per stream | 256 | `explainer.statements.count` |
| `solid` statement | 64 KiB canonical | `assembly.bytes` |
| Any other statement | 4 KiB | `stmt.bytes` |
| Beats per explainer, over all its streams | 16 | `explainer.beats.count` |
| Commands per beat | 12 | `beat.ops.count` |
| Checks per beat, 2D and 3D together | 8 | `beat.checks.count` |
| Highlight ids per beat | 16 | `beat.highlight.count` |
| Notes | 24 | `notes.count` |
| Note text | 60 | `notes.text.<id>` |
| Title (filled) | 80 | `explainer.title` |
| Caption | 200 | `stmt.say` |
| Caption `unchecked` | 60 | `beat.unchecked.<n>` |
| Nesting of a document | 63 levels | `explainer.depth` |
| Nesting of a stream statement | 64 levels (other than `solid`: 59, `lesson.depth`) | `explainer.depth` |
| Record of shown 2D item claims in a snapshot | 1024 ids, 3 tiers each, at most 81,936 bytes (part of the snapshot cap) | `snapshot.shown`, `snapshot.bytes` |
| Record of shown beat claims in a snapshot | 16 beats, a caption and 8 checks each, 3 tiers each, at most 5,776 bytes (part of the snapshot cap) | `snapshot.shown`, `snapshot.bytes` |
| Record of shown annotation claims in a snapshot | 80 annotations, one tier each, at most 8,976 bytes (part of the snapshot cap) | `snapshot.shown`, `snapshot.bytes` |

Board, lesson and assembly limits (`MGLimits`, `MGLessonLimits`, `MGSolidLimits`) are unchanged and apply inside.

## Reasons

Every reason is one token (ASCII letters, digits, `_`, `.`, `,`; at most 96 characters). In explainer-owned reasons
author text becomes a segment of letters, digits and `_`, at most 32 characters. Inner 2D, lesson and solid reasons
pass through with their wording. The catalog lists each with the format `explainer` (`marty-solid reasons`,
`MGSolidReasons.catalog`, [REASONS.md](REASONS.md)).

Explainer reasons: `explainer.json`, `explainer.object`, `explainer.number`, `explainer.depth`, `explainer.bytes`,
`explainer.version`, `explainer.kind`, `explainer.missing`, `explainer.unknown.<keys>`, `explainer.title`,
`explainer.primary`, `explainer.empty`, `explainer.header`, `explainer.statements.count`, `explainer.board`,
`explainer.board.steps`, `explainer.board.title`, `explainer.board.dim`, `explainer.board.missing`, `explainer.solid`,
`explainer.solid.version`, `explainer.solid.steps`, `explainer.solid.title`, `explainer.solid.missing`,
`explainer.beats`, `explainer.beats.count`, `explainer.op.title`, `explainer.id.duplicate.<id>`,
`explainer.id.view.<id>`, `notes.object`, `notes.count`, `notes.entry.<id>`, `notes.text.<id>`, `notes.view.<id>`,
`names.count`, `names.text.<n>`, `names.token.<n>`, `names.number.<n>`,
`notes.unused.<id>` (a warning; the strict check refuses it), `beat.object`, `beat.missing`, `beat.unknown.<keys>`,
`beat.unchecked.<n>`, `beat.ops`, `beat.ops.count`, `beat.check`, `beat.checks.count`, `beat.refused`,
`beat.highlight`, `beat.highlight.count`, `beat.highlight.ref.<id>`, `beat.highlight.stale.<id>` (in `hostIssues`
only), `stmt.json`, `stmt.kind`, `stmt.order`, `stmt.bytes`, `stmt.say`, `stmt.view.twice`, `stmt.highlight.twice`,
`lesson.depth`, `view.object`, `view.unknown.<keys>`, the step reasons renamed for a beat view (`view.focus`,
`view.camera`, `view.explode`, `view.orbit`, `view.spin`, `view.ghost`, `view.section`, `view.section.normal`,
`view.section.offset`, `view.section.parts`, `view.section.missing.<keys>`, `view.section.unknown.<keys>`,
`view.annotate`, `view.annotate.count`, `view.annotate.ref.<id>`) and for a 3D check (`check.unknown.<keys>`), the pose
rule for the explainer's own text (`text.pose.beat.<n>`, `text.pose.board`, `text.pose.title`), `text.number.beat.<n>`, `text.number.item.<id>`,
`text.number.control.<id>`, `text.number.template`, and for snapshots `snapshot.bytes`, `snapshot.number`,
`snapshot.depth`, `snapshot.kind`, `snapshot.version`, `snapshot.header`, `snapshot.header.missing`,
`snapshot.header.unknown.<keys>`, `snapshot.frozen`, `snapshot.beats`, `snapshot.next`, `snapshot.board`,
`snapshot.solid`, `snapshot.lesson`, `snapshot.setup`, `snapshot.controls`, `snapshot.pending`, `snapshot.json`, `snapshot.presented`, `snapshot.shown`, `snapshot.beat`, `snapshot.stream`.
Solid reasons an explainer gives itself: `tier.key`, `check.object`, `check.value`, `check.comparison`, `check.eq`,
`check.lt`, `check.gt`, `check.tol`, `check.fact.<name>`, `check.failed.<name>`, `text.sign.<name>`,
`text.modifier.<modifier>`, `text.modifier.<modifier>.<name>`, `report.engine`. The tool: `kind.unsupported`.

Reasons are developer tokens. Do not show them to the learner.

A 2D (plain-name) check and every other lesson command keep the lesson's own reasons (`check.<name>`,
`check.missing`, `check.unknown.<name>`, `control.*`, `animate.*`, …; see [LESSONS.md](LESSONS.md)); like scene and
patch reasons, they are not in the Solid catalog.

## The check report

`marty-solid check FILE.json [--strict] [--component C.json ...]` and `MGExplainerReport.check(data:library:profile:engine:)`
print ONE JSON object (sorted keys) for both views. The tool dispatches on the top-level `kind` after a bounded read
(128 KiB, regular files only): `"explainer"` takes this path, a lesson document (`"lesson"`) gives
`{"ok": false, "reason": "kind.unsupported"}` (exit 1), and anything else (no `kind`, `"assembly"`, another value)
takes the assembly path with its reasons unchanged. A file over 128 KiB is `explainer.bytes`
when its text holds `"explainer"`, else `assembly.bytes`. Exit codes: 0 ok, 1 refused or failed check, 2 usage or I/O.

| Key | Content |
| --- | --- |
| `ok`, `reason`, `strict`, `kind` (`"explainer"`), `version` (1) | `reason` is the first refusal |
| `location` | `{"view": "header" \| "board" \| "solid" \| "beat" \| "annotation" \| "stream", "beat", "statement", "command", "id", "detail"}` or null |
| `file` | `{"lines", "bytes", "sha256"}` |
| `title`, `primary` | the filled title; the primary view |
| `views` | `{"board": null \| {"items", "template", "values": {name: {value, unit, text, tier}}}, "solid": null \| {the assembly report fields}}` |
| `ids` | `{"board", "controls", "solid", "annotations"}` in canonical order |
| `beats` | per kept beat: `{"n", "caption", "template", "unchecked", "tier", "facts", "checks": [{"value", "comparison", "target", "tol"}], "highlight": {"board", "solid", "annotations"}, "view"}` |
| `annotations` | one entry per 3D annotation: the assembly report's `annotations` (`views.solid` also holds its `placements`) |
| `legend` | `{"text", "groups": {"solved", "schematic", "given", "described"}, "notes", "claims"}` |
| `warnings` | `notes.unused.<id>`, then the solid's warnings, then one `annotation.anchor.hidden.<id>` or `annotation.anchor.untested.<id>` per beat anchor issue, then one `annotation.arrow.hidden.<id>` or `annotation.arrow.untested.<id>` per beat arrow issue, then one `annotation.arrow.dropped.<id>` per arrow a beat still drops (`"view": "beat"`), then one `framing.cut.beat.<n>` per beat still that cuts a solid part (`"view": "beat"`, `id` the first cut part), then one `unit.small.<id>` per small named unit (`"view": "solid"`), each `{"reason", "view", "id"}` |
| `anchorIssues`, `anchorUntested` | with 3D annotations only: every label and pointer anchor issue (off part, then the beats in order), each with `suggest`, `noSuggest` and `repair` ([SOLID-3D.md](SOLID-3D.md#anchor-suggestions)), and the anchors a beat's test budget left untested ([SOLID-3D.md](SOLID-3D.md#anchor-checks)); `views.solid` holds neither |
| `anchor` | with a refusal for an anchor reason only: the issue it names (`id`, `beat`, `cause`, `by`, `fix`, `suggest`, `repair`, …) |
| `arrowIssues` | with 3D annotations only: every arrow a beat still does not show well enough (beats in order), each with the visible share, the part in the way, `suggest` (a move of the arrow), `noSuggest` and `repair` ([SOLID-3D.md](SOLID-3D.md#arrow-visibility)) |
| `arrowDrops` | only when a beat still drops an arrow: `[{"id", "reason", "part", "by", "step", "beat"}]`, the force and flow arrows whose part the beat's camera cannot see, so the still does not draw them; a warning, never refused ([SOLID-3D.md](SOLID-3D.md#arrow-drop)) |
| `framingCuts` | only when a beat still cuts a solid part: `[{"step", "beat", "parts", "ghost", "repair"}]`, the parts its explicit `focus` close-up cuts and the beat view's whole `ghost` list that makes them see-through context; a warning, never refused ([SOLID-3D.md](SOLID-3D.md#rendering-camera-framing-and-the-loop)) |
| `smallUnits` | only when a named unit is small in every beat still that shows it: `[{"unit", "pixels", "minimum", "stills", "step", "beat", "repair"}]`; a warning, never refused ([SOLID-3D.md](SOLID-3D.md#rendering-camera-framing-and-the-loop), "Small named units") |
| `arrow` | with a refusal for an arrow reason only: the issue it names |
| `limit` | with a refusal from a length, count or size limit only: `{"field", "actual", "limit", "unit"}` (+ `minimum`; `actualAtLeast` or `actualAtMost` instead of `actual` for a bound); `field` is a path into the document such as `title`, `notes.t3.basis`, `beats[2].say` or `solid.annotations.labels[0].text` ([REASONS.md](REASONS.md#limit-details)) |
| `repair` | with a refusal only: one line for a model, built from `arrow`, `anchor`, `limit` or the catalog meaning (at most 400 Unicode scalars) |
| `budget` | `{"bytes", "limit", "statements", "triangles", "triangleLimit"}` |
| `engine` | the engine identity |

Refusal order after the document loads: the solid's report checks (`check.meshOpen`, `check.gearsInterpenetrate`),
then with `--strict` the solid's strict refusals (`joint.idle.<id>`, `frame.axis.off.<id>`, `annotation.unused.<id>`,
`annotation.anchor.off.<id>`), `notes.unused.<id>`, then `annotation.anchor.hidden.<id>` or
`annotation.anchor.untested.<id>` of the first beat still that does not show, or did not test, a label's or pointer's
anchor, and last `annotation.arrow.hidden.<id>` or `annotation.arrow.untested.<id>` of the first beat still that does
not show an arrow well enough (less than half of its samples or its head visible), or did not test it. For the anchor
reasons `location` is `{"view": "beat", "beat": <0-based beat>, "id": <annotation>, "detail": <cause>}`
(`occluded`, `hidden`, `ghosted`, `offscreen`, `untested`) and `anchor` names the part in the way, a fix and `suggest`
(an anchor that passes in every beat that shows the label) or `noSuggest`; for the arrow reasons `detail` is `hidden`
or `untested` and `arrow` gives the visible share, the part in the way and `suggest` (a move of the arrow that shows it
in every beat that shows it, [SOLID-3D.md](SOLID-3D.md#arrow-visibility)) or `noSuggest`. The beat test frames each beat as `marty-solid render` frames its still at 1280 × 800: the beats are
played in a speech-paced session so each beat's board pane and pane width are the render's, and the pane camera uses the
unblocked-focus rule with its automatic ghosts ([SOLID-3D.md](SOLID-3D.md#anchor-checks)).
The report is printed in full either way, so the author can repair from it.

`marty-solid render FILE.json NEW_DIR [--size WxH] [--no-loop] [--loop-fps 10|30] [--no-story] [--story-fps 10|30]
[--snapshots]` writes `board-0.png`
and `solid-0.png` (the views before the first beat), one composite `beat-<n>.png` per beat (side by side the board pane
fits its content, 28–50 % wide, see [Board pane width](#board-pane-width); stacked when the size is taller than wide, with
the `primary` pane 55 % high, the caption band and the legend line with its notes; the board pane follows the adaptive
rule below, and each beat's manifest record says `boardPane`), `loop.gif` and `loop.mp4` (the solid's
loop, as for an assembly; skipped with `--no-loop` or without a solid), `story.mp4` (the beats in order with their
captions, views, highlights, annotations and cameras, the board at each beat's settled state and the legend line in every
frame; the timing rules, the 3,600-frame cap `story.frames` and the manifest record are in
[SOLID-3D.md](SOLID-3D.md#rendering-camera-framing-and-the-loop); skipped with `--no-story`), `snapshot-beat-<n>.json` with `--snapshots`
(snapshot `/2` of each beat's view) and `manifest.json` (source, outputs with bytes and SHA-256, legend, captions, frames
and seconds per frame). The legend line and the manifest `legend` are the legend of the whole explainer, every beat
presented (the legend `check` reports). The solid pane of a beat is framed by the step the beat shows, with the assembly rule
([SOLID-3D.md](SOLID-3D.md#rendering-camera-framing-and-the-loop)); the pane holds no title or caption, so all of it
is the safe window.

## What is not checked

* Words. A caption or a 2D text is checked for numbers only, not for meaning.
* 2D geometry: positions, vector directions, region shapes and plot points are drawn as authored.
* Data with a `basis` note: the engine shows it as given; it does not check the source.
* Highlights are presentation only; they never prove anything.
* The 3D view per beat is the solid step view (cuts, ghosts, explode, camera, orbit, spin). Beats cannot change the
  solid (no 3D patches in beats), and learner controls bind 2D template parameters only.
* No clip export, no on-device timing. Annotation placement in the SwiftUI pane is checked through the core frame
  record, not on a device.
