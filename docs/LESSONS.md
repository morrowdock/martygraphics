# Beat-by-beat lessons

A lesson is a short sequence of beats. Each beat has one spoken line and the commands that change the board.
The engine validates every command, computes every number on screen and keeps one persistent state.
A touch control and a scripted beat send the same command to the same state.

Status: phase 1. The core, the SwiftUI lesson view and one demonstration ([rotation lesson](../Examples/LessonDemo/README.md))
are in the package. The scene format `v: 1` and the patch format `v: 1` do not change.

## Three layers

| Layer | What it is | Where |
| --- | --- | --- |
| L1 intent | A lesson document or a statement stream. Untrusted data: closed keys, bounded sizes, no code. | `MGLesson`, `MGLessonSession.feed` |
| L2 commands | The existing patch ops plus `animate`, `bind`, `unbind` and `check`. Each command is applied to a copy of the state, and the whole scene is validated again. | `MGLessonEngine` (internal) |
| L3 state | `MGLessonState`: the validated `MGScene`, the beat cursor, the bound controls and the id history. | `MGLessonSession.state` |

Rules:

1. A renderer reads only L3.
2. A control has no value of its own. Its value is `scene.source.params[param]`. A slider and a script cannot disagree.
3. Every number the learner sees comes from engine values (`MGScene.values`) through `{name}` placeholders.
4. L2 and L3 import only Foundation. `MartyGraphicsLessonView.swift` is the only SwiftUI file of the lesson layer.

## Lesson document

```json
{"v":1,"kind":"lesson","title":"Rotating a triangle",
 "scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}},
 "beats":[
  {"say":"Now we turn the triangle about the origin O by {theta}.",
   "ops":[{"op":"animate","param":"angle","to":90,"dur":1.5}]},
  {"say":"A moved from ({ax0}, {ay0}) to ({ax}, {ay}).",
   "check":[{"value":"ax","eq":-1},{"value":"ay","eq":2}]}
 ]}
```

- Top-level keys: `v` (must be 1), `kind` (must be `lesson`), `title` (optional), `scene` (a v1 scene), `beats` (1–24).
- Beat keys: `say` (required), `ops` (0–12 commands), `check` (0–8 checks).
- The scene may not have `steps` (`lesson.scene.steps`). A lesson has one beat system.
- A template's own walkthrough is dropped in a lesson: every resolved item is on the board from the start and no
  template step edit applies, so the lesson state and the board always hold the same items (for example `bst` with
  `find` shows all its path highlights at once). The scene `source` is unchanged, and the same scene outside a lesson
  keeps its v1 walkthrough.
- `MGLessonSession.load` is all-or-nothing. The engine validates the document statement by statement in a fresh session.
  The first problem refuses the whole document, with its location. The current lesson stays as it was.
- Fixtures: [`rotation.lesson.json`](fixtures/v1/rotation.lesson.json) and the same lesson as statements,
  [`rotation.statements.ndjson`](fixtures/v1/rotation.statements.ndjson).

## Statement stream (one JSON object per statement)

A model can write the lesson as a stream. `MGLessonSession.feed(_:)` takes raw text chunks.
`MGLesson.statements` flattens a document into the same stream. Both give the same final state (test U14).

| Statement | Form | Rule |
| --- | --- | --- |
| header | `{"lesson":{"v":1,"title":"…"}}` | Optional. First statement of a stream only. |
| scene | `{"scene":{…v1 scene…}}` | Once per stream. A scene in a new stream replaces the lesson. |
| keep | `{"keep":true}` | First statement of a follow-up stream. State, ids and controls stay. Beat numbers continue. |
| say | `{"say":"…{name}…"}` | Starts a beat. Up to 200 characters. |
| command | `{"op":…}` | Belongs to the open beat. Commands between the scene and the first `say` are set-up commands and show with the scene. |
| check | `{"check":{"value":"ax","eq":-1}}` | Belongs to the open beat. |
| end | `{"end":true}` | Optional. `endStream()` does the same. |

Streaming rules:

- Partial input is ignored until a statement is complete. A statement is complete at the closing bracket of a top-level
  `{…}` or `[…]` value. Braces, escaped quotes and `\n` inside strings do not end a statement (test S1).
- Each statement is validated as soon as it is complete, against the projected state (the state after every accepted statement).
- A refused statement changes nothing. Earlier marks stay. Later statements continue (test S2).
  A refused `say` does not close the open beat: later commands keep attaching to it.
- Input after a finished lesson starts a candidate stream with its own budget. Playback (`isComplete`) reopens only
  when that stream's `keep` or `scene` is accepted, so refused input after the end changes nothing.
  A later statement that names a refused id is refused with its own reason, for example `highlight.target`.
- Text between statements that is not whitespace is skipped up to the next `{` or `[`. It is reported once (`stmt.json`).
- The scene is presented at once. That is the first visible result (`firstPresented`).
- A beat is presented only when it is complete: the next `say`, `end` or `endStream()`. So a failing check can refuse the
  beat before the learner sees it.

## Commands

| Command | Form | Notes |
| --- | --- | --- |
| add | `{"op":"add","item":{…}}` | Existing patch op. A highlight is `{"id":"hiA","k":"highlight","target":"vA"}`. |
| set | `{"op":"set","id":"vA","key":"label","value":"…"}` | Existing. `id` and `k` cannot change (`patch.set.key`). |
| remove | `{"op":"remove","id":"hiA"}` | Existing. Template items become hidden. |
| params | `{"op":"params","params":{"angle":90}}` | Existing. The template computes every value again. |
| camera, title | `{"op":"camera",…}`, `{"op":"title",…}` | Existing. |
| animate | `{"op":"animate","param":"angle","to":90,"dur":1.5}` | New. Commits `params` once. The view plays engine keyframes. |
| bind | `{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}` | New. A learner slider for one numeric template parameter. |
| unbind | `{"op":"unbind","id":"angle"}` | New. |
| check | `{"check":{"value":"ra","eq":2.24}}` or `beats[i].check[]` | New. The engine proves a claim. |

`step`, `steps` and `dim` are refused in a lesson (`lesson.op.<name>`).

### animate

- The state after `animate` is the state after `params` with the same value: the same canonical source, items, values and revision.
- The engine makes keyframes: one every 5° for a parameter in degrees, else 36. Each keyframe is a fully validated scene.
  If one keyframe does not validate, the command is refused (`animate.frame`, inner reason in `detail`).
- `dur` 0.2–6 s (default 1.5). At most 72 keyframes, so one `animate` turns at most 360°.
- Only scalar, non-integer template parameters animate (`animate.param`).

### bind

- `param` names a numeric template parameter (`control.param`). `min` < `max`, both inside the parameter range (`control.range`).
- `0 < step ≤ max − min` (`control.step`). `step` is a UI hint. The engine accepts any value in `min…max`.
- `label` is fixed text. A placeholder is refused (`control.label.placeholder`): a number filled in once would go
  stale when the value changes. The slider shows the current value next to the label.
- At most 4 controls (`control.count`). Control ids use the item id grammar in their own namespace (`control.duplicate.<id>`).
- `k` is `slider` only (`control.kind`).

### check

- `value` names an engine value. An unknown name is `check.unknown.<name>`.
- `eq` without `tol` compares what the learner sees: `MGPhysics.format(value) == MGPhysics.format(eq)`.
- `eq` with `tol`: `|value − eq| ≤ tol`. `lt` and `gt` compare numbers.
- A check is a claim about what the learner sees at the end of the beat:
  - A check that is false when it arrives refuses the whole beat (`check.<name>`). The projected state goes back to
    the start of the beat. The beat's later statements are refused as cascades (`beat.refused`).
  - A later command in the same beat that would make an accepted check false is refused alone, with that check's
    reason (`check.<name>`). The beat and its proven claims stay.
  - Every check is evaluated again on the beat's final state before its line is queued, and on the exact state
    that is about to be presented (a learner change can make it false; the beat is then refused).

### Text rule (owner decision D3)

Lesson text may not contain a decimal number literal such as `1.23`, `.5`, `-.5` or exponent notation such as
`2e3` / `2E-3` (`text.literal`). This applies to `say`, labels, titles
and every string in a command or scene statement. Integers such as "90°" stay allowed. Decimals come from `{name}`.
Engine-filled text (for example the label "A (0.71, 2.12)") is not affected.

## Stable ids

- Item ids keep the scene grammar: 1–24 ASCII letters, digits or `_`, letter first, unique in the resolved scene.
- An id that was removed can come back only with the same kind (`lesson.id.kind.<id>`).
- Template ids depend on the parameter shape, not the values. A turn of any angle keeps every `rotate2d` id (test U3).
- Control ids are a separate namespace.
- `MGLessonState.introduced` records the beat that added each id. `describe(id)` returns facts for "ask about this part".

## Touch and script share one state

```
Slider ──value v──► MGLessonController.control("angle", v)      (snaps v to the step: UI only)
                        │
                        ▼
              MGLessonSession.control("angle", v)
                        │ gate: control bound (control.unknown.<id>), min ≤ v ≤ max (control.value)
                        │ builds {"op":"params","params":{"angle":v}}, origin learner
                        ▼
              the SAME command path as a scripted beat ──► new state, or refusal (state unchanged)
```

- A learner value is refused, never clamped.
- `apply(_:origin: .learner)` accepts only `params` changes of bound parameters (`control.op`, `control.unknown.<param>`).
  Several parameters are checked in sorted name order, so the reported reason never depends on dictionary order.
- Owner decision D2: after the learner moves a slider, a later beat keeps the learner's value unless the beat sets it.
  At a beat's due time the engine applies its commands again to the presented state. A command that no longer validates is
  refused alone. A check that no longer holds refuses the beat. Beats that make value claims should set the value
  (the demonstration's last beat animates to 180° and then checks).
- The transition depends on the origin: learner → `direct` (no blend, no draw-on replay); script → `blend`; `animate` → `keyframes`.

## Spoken beats and timing events

Events come in order. `MGLessonSession.history` keeps each event with a time from the injected `MGLessonClock`.

| Event | When |
| --- | --- |
| `accepted(statement)` | A complete statement was validated. |
| `refused(issue)` | A statement, command or learner value was refused. |
| `firstPresented` | A scene statement is on the board (core time to first visible). |
| `lineQueued(beat, text)` | A beat is complete and valid. Text is filled from the projected state. |
| `lineDue(beat, text, changed)` | A beat is next. Text is filled from the presented state. `changed` is true when the learner moved a value since `lineQueued`. |
| `lineStarted(beat)`, `lineEnded(beat)` | The host reported speech start and end (or `.estimate` pacing ended the line). |
| `beatPresented(beat)` | The beat's commands are in the presented state. |
| `streamEnded` | Every statement was received and validated. |
| `lessonComplete` | The last line ended and the last transition settled (keyframes: their duration; blend: 1.2 s), or `finishNow()`. Set-up and host `apply` transitions count too; a new scene starts with no pending settle time. |

Pacing (`MGPacing`):

- `.speech`: the next beat waits for `lineEnded(k)`. `lineEnded` for a line that is not open is ignored and recorded in
  `hostIssues` (`line.order`).
- `.estimate(wordsPerSecond:)`: line length = words / rate, clamped to 1–12 s. Call `tick()` at `nextWake`.
- `.immediate`: each beat as soon as it is complete.

Host calls: `lineStarted`, `lineEnded`, `finishNow` (present everything now), `pause`, `resume`, `tick`.
While paused, statements still validate and `lineQueued` still comes. No line becomes due.

Time to first visible and time to complete are separate numbers. `MGLessonController.timing` records the request time
(`begin()`), `firstPresented`, the first Canvas frame of the lesson view, `streamEnded` and `lessonComplete`.
The view also writes `OSSignposter` intervals (subsystem `MartyGraphics`, category `lesson`): `statement` and `beat`.

## Persistence

`snapshot()` returns engine data only: the scene source and revision, the beat cursor, controls, id history, beats received
but not presented, and the pacing position. `restore(_:pacing:clock:)` validates everything again with the engine.
A snapshot that does not validate is refused with a reason (for example `template.unknown`). It is never loaded in part.
The event history and the command log start empty after a restore.
A snapshot covers complete statements only. A statement that has started but not finished is not stored; replay
`unfinishedInput` into the restored session (`feed(_: Data)`) before the rest of the stream. Those bytes are not in the
snapshot's byte count, so the budget is the same after the replay.

## Renderer behaviour

- `MGSceneController.show(_:transition:)` and `apply(patch:requireRevision:transition:)` take an `MGTransition`.
  The existing `show(_:)` and `apply(patch:)` keep `.blend`. Existing boards behave as before.
- `.direct` adopts without blend and without draw-on for ids that were already on the board. Before this change every
  update blended with a spring, so a board followed a finger late, with overshoot.
- `.keyframes` plays one timed segment per `animate`, each over its own `dur`, and blends only between neighbouring
  frames of one segment (at most 5° apart). Between two segments the board cuts: a change between two `animate`
  commands in one beat is not tweened, so no chord is drawn across it. The old linear point blend put a
  turning vertex on the chord: at the middle of a 90° turn it was at 71 % of its distance to the pivot (guard test in U10).
  Labels show the number of the nearer keyframe, so a label never shows a number that no frame computed.
  Ids that the beat adds after the turn draw on when the turn ends.
- `MGAdoption.plan` is the pure decision (blend, draw-on ids, keyframe segments). The SwiftUI host and the tests use it (R1–R3).
- `MGSceneController.pauseTransitions()` / `resumeTransitions()` hold an in-flight keyframe animation on its current
  frame (`MGTransitionClock`). `MGLessonController.pause()` calls it, and the session's settle time continues after
  `resume()` from where it stopped.

## Limits and reasons

Limits (owner decision D5; scene limits in `MGLimits` do not change):

| Limit | Value | Reason |
| --- | --- | --- |
| Beats per lesson or stream | 24 | `lesson.beats.count` |
| Commands per beat | 12 | `beat.ops.count` |
| Checks per beat | 8 | `beat.checks.count` |
| Statement size | 4 KiB | `stmt.bytes` |
| Lesson or stream size | 32 KiB | `lesson.bytes` |
| Statements per stream (accepted or refused) | 256 | `lesson.statements.count` |
| Bound controls | 4 | `control.count` |
| `animate` duration | 0.2–6 s | `animate.dur` |
| Keyframes per `animate` | 72 (360°) | `animate.to` |

Stream budget: every received byte counts toward the 32 KiB, including whitespace, garbage, oversized and
unfinished text. Past the byte or statement limit the session emits one terminal refusal and ignores the rest of the
stream until `endStream()`. A document's size is the size of the statement stream it becomes (`MGLesson.statementStream`).
Input over 64 KiB is `lesson.bytes` without parsing.

New reasons (closed list). Inner engine reasons (`patch.set.ref`, `id.duplicate.<id>`, `highlight.target`,
`template.<param>`, `item.kind`, `patch.op.<name>`, …) pass through with their wording unchanged (token-normalised). The location is in separate fields:
`MGLessonIssue.beat`, `.statement`, `.command`, `.origin`, `.detail`.

`lesson.json`, `lesson.object`, `lesson.version`, `lesson.kind`, `lesson.title`, `lesson.unknown.<keys>`, `lesson.scene`,
`lesson.scene.steps`, `lesson.beats`, `lesson.beats.count`, `lesson.bytes`, `lesson.op.<name>`, `lesson.id.kind.<id>`,
`lesson.empty`, `lesson.missing`, `scene.object`, `beat.object`, `beat.missing`, `beat.unknown.<keys>`, `beat.ops`, `beat.ops.count`, `beat.check`,
`beat.checks.count`, `beat.refused`, `stmt.json`, `stmt.bytes`, `stmt.kind`, `stmt.order`, `stmt.say`,
`stmt.say.placeholder.<name>`, `stmt.say.brace`, `line.order`, `control.object`, `control.missing`, `control.unknown.<keys|id|param>`,
`control.id`, `control.kind`, `control.param`, `control.range`, `control.step`, `control.label`, `control.count`,
`control.duplicate.<id>`, `control.value`, `control.op`, `control.label.placeholder`, `lesson.statements.count`, `unbind.id`, `animate.missing`, `animate.unknown.<keys>`,
`animate.param`, `animate.to`, `animate.dur`, `animate.step`, `animate.frame`, `check.object`, `check.missing`, `check.unknown.<keys|name>`,
`check.value`, `check.comparison`, `check.eq`, `check.lt`, `check.gt`, `check.tol`, `check.<name>`, `text.literal`,
`snapshot.<field>`.

Every reason is one token: ASCII letters, digits, `_`, `.` and `,`, at most 96 characters. In lesson-owned reasons
(lesson, beat, check, control, `animate` and `unbind` keys and ids), author text becomes a segment of letters, digits
and `_` only (other characters become `_`), at most 32 characters. Inner engine reasons (scene, item and patch
parsing) keep their own wording and are only token-normalised, so an author key there can still contain `.`.
Only `animate.frame` carries an inner reason, in `detail`. `MGTween.keyframes` refuses a `maxStep` that is not
finite and positive (`animate.step`).

Reasons are developer tokens. Do not show them to the learner.

## The `rotate2d` template (opt-in `MGGeometryPack`)

Register it once per process: `try MGPacks.register(MGGeometryPack.pack)`. Without it, `rotate2d` is `template.unknown`.

- Parameters: `pts` 3–6 vertices `[x, y]` in −4.5…4.5; `angle` −360…360° (default 0); pivot `px`, `py` −2…2 (default 0);
  `ghost` 0 or 1 (default 1).
- Maths, in Double: x′ = px + (x − px)·cos θ − (y − py)·sin θ, y′ = py + (x − px)·sin θ + (y − py)·cos θ.
- Board: world 14 × 10, origin O at world (7, 5).
- Items: `xaxis`, `yaxis`, `ghost` (when `ghost` = 1), `shape`, `vA…`, `lA…` ("A (x, y)"), `pivot`, `arc`, `ltheta`.
- Values: `theta` (°), `ax ay bx by …` (turned), `ax0 ay0 …` (original), `ra rb …` (distance to the pivot), `px`, `py`.
- Refusals: `template.pts.radius` (a vertex's circle would leave the board), `template.pts.area` (area < 0.25),
  `template.pts.gap` (vertices closer than 0.6), `template.pts.count`.
- Coordinate labels are placed by a fixed search: outward from the shape's centre first, then turned in 30° steps,
  until the label clears every vertex, the pivot and earlier labels. A test checks every 5° at 1024 × 768 and 1366 × 1024 (R5).

## Measured timing (this Mac only)

Apple M1 Mac, macOS 27.2, Swift 6.4.2, release build, 2026-11-06
(`swift run -c release --package-path Examples/LessonDemo lesson-demo --timing`). These are not iPad numbers.
The proposed budgets apply to a physical-device receipt, which is pending.

| # | Measure | Median | p95 |
| --- | --- | --- | --- |
| T1b | Scene statement complete → `firstPresented` (core) | 0.162 ms | 0.219 ms |
| T1 | Scene statement complete → first offscreen frame, 1024 × 768 (`ImageRenderer`) | 0.494 ms | 0.957 ms |
| T2 | Learner control tick → state committed | 0.148 ms | 0.158 ms |
| T3 | `animate` 0 → 180° (36 keyframes) ready | 4.438 ms | 5.004 ms |
| T4a | Whole rotation lesson fed → `streamEnded` (no model) | 5.582 ms | 5.842 ms |
| T4b | `lineDue(0)` → `lessonComplete` at `.estimate(2.5)` (injected clock, pacing arithmetic) | 24.8 s | — |

T1 is an offscreen render, not an on-screen frame. The first scene needs 136 bytes of stream (header and scene).

## What is not checked

- No on-device (iPad) timing, and no XCUITest UI test. The example's tests run on an iPad simulator through
  `xcodebuild test`; they render the demo view offscreen and drive the controller, not real touches.
- Narration that a model writes as prose is not checked, except through `check` and the D3 decimal rule.
- `rotate2d` does not detect self-intersecting polygons.
- Labels can still overlap the shape's edges, the arc or a highlight's box. Only label-to-label and label-to-dot overlap is tested.
- A removed template item cannot come back (the patch format has no un-hide). Adding it again is refused.
- The legacy 3D board (`MG3DView`) still rebuilds every node on any change. Lessons in this phase are 2D. Recorded for a follow-up.
- Solid 3D lessons, a 2D expression language, dragging items on the board, and a toggle control are not in phase 1.
- VoiceOver, Dynamic Type and Reduce Motion behaviour of the lesson view were not checked on a device.
  With Reduce Motion on, the host skips keyframes and draw-on (existing host rule).
