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
| `view` | the 3D view of the beat: `focus`, `explode`, `camera`, `orbit`, `spin`, `section`, `ghost` (step rules); needs `solid` | `view.object`, `view.unknown.<keys>`, step reasons renamed `step.` → `view.` (`view.section.parts`, `view.camera`), `ref.unknown.<id>`, `section.*`, `assembly.budget`, `explainer.solid.missing` |

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
4. Highlight is presentation: it changes no state and is never a claim. At presentation every id is resolved again; an
   id that no longer resolves is dropped and recorded in `hostIssues` (`beat.highlight.stale.<id>`).
5. A beat settles when its 2D transition settles and its 3D `spin` has played (4 s per input turn,
   `MGExplainerLimits.spinSecondsPerTurn`). `.immediate` pacing skips motion in both views.
6. A failing check, 2D or 3D, refuses the whole beat: the 2D state goes back to the beat's start, the beat's view,
   highlight and 3D checks are dropped (a dropped view releases its cut budget), and its later statements are
   cascades (`beat.refused`). A refused `view`, `highlight` or command is refused alone; the beat keeps the rest.
7. A refused statement changes nothing: 2D state, 3D views, cut cache, budget counters, legend, timers.
8. A beat's `view.section` is cut when its statement is accepted. The cut counts toward the document's mesh budget
   (`assembly.budget`) and section work budget (`section.budget`) with every other kept view.

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

SEAM (open-vocabulary PR 3a): 3D annotation ids (labels, arrows, dimensions) join this namespace, the claims and the
check report once `annotations` merges. Until then `annotations` in a solid is refused with the assembly's own reason
(`assembly.unknown.annotations`).

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
strings of `set` and `add` commands, unless the item has a note (`text.number.item.<id>`). A control label may not
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

`MGExplainerSession.claims` lists the claims in this order: 3D motion (part order), (PR 3a: annotations), the title,
`board.template`, 2D items `item.<id>` (board order, then `add` order), then per kept beat `beat.<n>` and its checks
`beat.<n>.check.<k>`. The one legend (`MGExplainerLegend`, owner D4) shows `Solved N · Schematic N · Given N · Not
checked N` (each group only when non-zero). `Schematic` counts Built claims of every kind except `data`; `Given`
counts Built `data` claims (noted 2D items), so a 3D-only explainer has its assembly's own legend text (test T9).
Notes: "Some motion is schematic" when a motion claim is below Solved; "Shapes and drawings as authored", always.

`describe(_:)` routes by member: a 2D id gives the lesson's describe, a table sub-address the table's plus `row` (and
`column`), a 3D part, anchor or `repeat` base the solid's describe, an instance its parts; an unknown id gives nil.

## Statement stream

`MGExplainerSession.feed(_:)` takes raw text; `MGExplainer.statements` flattens a document into the same stream (both
give the same final state, test S1). Fixture: [`explainer-mixed.statements.ndjson`](fixtures/v1/explainer-mixed.statements.ndjson).

| Statement | Form | Rule |
| --- | --- | --- |
| header | `{"explainer": {"v": 1, "title"?, "primary"?, "notes"?}}` | Required first statement of a new stream (`explainer.header`). A header in a later stream replaces the explainer. |
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
`explainer`: `statement`, `beat`, `solidCompile`). `MartyGraphicsExplainerView` shows the two panes (the `primary` one
larger; side by side when wide, stacked when tall), the caption and the legend. No device budget is claimed: a
physical-device receipt is pending. Authoring advice: write the view the learner needs first, keep the board small,
and put a large solid after a small board.

### Persistence

`snapshot()` holds engine data only: the header, the views as authored (as JSON text), each beat's caption, view,
highlight and checks, the lesson snapshot (as JSON text, so its nesting never adds to the explainer's) and the stream
position. `restore(_:pacing:clock:library:)` compiles the solid again, restores the lesson with the explainer's
environment and proves every 3D check again. The first problem refuses the whole snapshot with its reason (the
solid's own reason when it no longer compiles, `snapshot.<field>` otherwise); it is never loaded in part.

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
`notes.unused.<id>` (a warning; the strict check refuses it), `beat.object`, `beat.missing`, `beat.unknown.<keys>`,
`beat.unchecked.<n>`, `beat.ops`, `beat.ops.count`, `beat.check`, `beat.checks.count`, `beat.refused`,
`beat.highlight`, `beat.highlight.count`, `beat.highlight.ref.<id>`, `beat.highlight.stale.<id>` (in `hostIssues`
only), `stmt.json`, `stmt.kind`, `stmt.order`, `stmt.bytes`, `stmt.say`, `stmt.view.twice`, `stmt.highlight.twice`,
`lesson.depth`, `view.object`, `view.unknown.<keys>`, `text.number.beat.<n>`, `text.number.item.<id>`,
`text.number.control.<id>`, `text.number.template`, and for snapshots `snapshot.bytes`, `snapshot.number`,
`snapshot.depth`, `snapshot.kind`, `snapshot.version`, `snapshot.header`, `snapshot.header.missing`,
`snapshot.header.unknown.<keys>`, `snapshot.frozen`, `snapshot.beats`, `snapshot.next`, `snapshot.board`,
`snapshot.solid`, `snapshot.lesson`, `snapshot.items`, `snapshot.presented`, `snapshot.beat`, `snapshot.stream`.
Solid reasons an explainer gives itself: `tier.key`, `check.fact.<name>`, `check.failed.<name>`, `text.sign.<name>`,
`text.modifier.<modifier>`, `text.modifier.<modifier>.<name>`, `report.engine`. The tool: `kind.unsupported`.

Reasons are developer tokens. Do not show them to the learner.

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
| `ids` | `{"board", "controls", "solid", "annotations"}` in canonical order (`annotations` stays empty until PR 3a) |
| `beats` | per kept beat: `{"n", "caption", "template", "unchecked", "tier", "facts", "checks": [{"value", "comparison", "target", "tol"}], "highlight": {"board", "solid", "annotations"}, "view"}` |
| `annotations` | empty until PR 3a |
| `legend` | `{"text", "groups": {"solved", "schematic", "given", "described"}, "notes", "claims"}` |
| `warnings` | `notes.unused.<id>`, then the solid's warnings, each `{"reason", "view", "id"}` |
| `budget` | `{"bytes", "limit", "statements", "triangles", "triangleLimit"}` |
| `engine` | the engine identity |

Refusal order after the document loads: the solid's report checks (`check.meshOpen`, `check.gearsInterpenetrate`),
then with `--strict` the solid's strict refusals (`joint.idle.<id>`, `frame.axis.off.<id>`) and `notes.unused.<id>`.
The report is printed in full either way, so the author can repair from it.

`marty-solid render FILE.json NEW_DIR [--size WxH] [--no-loop] [--snapshots]` writes `board-0.png` and `solid-0.png`
(the views before the first beat), one composite `beat-<n>.png` per beat (the `primary` pane 55 % wide, stacked when
the size is taller than wide, the caption band and the legend line), `loop.gif` (the solid's loop; skipped with
`--no-loop` or without a solid), `snapshot-beat-<n>.json` with `--snapshots` (snapshot `/2` of each beat's view) and
`manifest.json` (source, outputs with bytes and SHA-256, legend, captions, frames and seconds per frame).

## What is not checked

* Words. A caption or a 2D text is checked for numbers only, not for meaning.
* 2D geometry: positions, vector directions, region shapes and plot points are drawn as authored.
* Data with a `basis` note: the engine shows it as given; it does not check the source.
* Highlights are presentation only; they never prove anything.
* The 3D view per beat is the solid step view (cuts, ghosts, explode, camera, orbit, spin). Beats cannot change the
  solid (no 3D patches in beats), and learner controls bind 2D template parameters only.
* No 3D annotations yet (PR 3a), no clip export, no on-device timing.
