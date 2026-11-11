# The brief and every attempt: brushless outrunner motor

**Hand-built.** A Claude agent (Claude Fable 5.2) wrote [`motor.json`](motor.json) by hand for this question:
"What is inside a drone's brushless motor, and what makes it turn?" It is not the output of Marty's question-to-lesson loop. The MartyGraphics engine at main
`ca2218131e897f1138fa80c0cf23cf21cd23fa4d` checked every attempt (`marty-solid check --strict`, release build) and
rendered the accepted file. Nobody changed a rendered frame.

**Fact-check fixes.** Attempt 6 is by Claude Opus 5.5. It applies the merged fixes of two independent fact
checks (Sol and Gemini, 2026-11-11; see [`../FACTS.md`](../FACTS.md)) to caption and label words only. It was
checked and rendered with a second release build of the same engine source (executable SHA-256
`21b76c201f144fd2d618d89e84cc3b8ccc4d275c316bb9960ed78f6669e6bc40`; the first build's SHA-256 differs. The second build ran in another build directory, and its reports for the
first-round documents are the same as the first build's, minus the engine identity).

## The brief (exact, written before attempt 1)

```text
Explainer brief: brushless outrunner motor (written before the first attempt, 2026-11-11)

Question: "What is inside a drone's brushless motor, and what makes it turn?"

Show, with the existing MartyGraphics solid engine at main (no engine change):

1. A brushless outrunner: the outer shell (the bell) turns with the propeller; the middle (the stator) is fixed.
2. A cutaway of the bell: permanent magnets on the inside of the bell, coils of copper wire on the stator teeth.
3. An exploded view along the shaft: bell with magnets, shaft, stator with coils, two bearings, base.
4. The counts, taken from the model by the engine: 12 coils (one on each stator tooth), 7 north and 7 south magnets
   (14 poles). This is the common "12N14P" drone motor layout.
5. The three phases: the 12 coils are joined in three groups (A, B, C). In the usual 12N14P winding each phase is
   two pairs of neighbouring coils on opposite sides of the stator (tooth order A a b B C c a A B b c C).
6. Commutation in words: the speed controller (ESC) switches current between the phases in a repeating order, the
   stator field turns, the magnets follow. One turn of the bell takes as many electrical cycles as there are magnet
   pole pairs (7 here).
7. Swap any two of the three wires and the motor turns the other way.
8. A last step that says what the engine checked and what it did not.

Rules I set for myself:

* The engine must solve the bell's rotation and count the coils and magnets (`repeat` counts as facts). Every number
  in a caption must be an engine fact (rule N1).
* Currents, magnetic forces and torque are NOT modelled. Say so. Do not claim which coil pulls which magnet at a
  given angle: the engine cannot check it.
* Count every `marty-solid check --strict` run as one attempt. Keep refused attempts.
```

## Every attempt

One attempt is one run of `marty-solid check --strict` on a candidate file. All attempts count. No attempt was
dropped or run again under the same number. The full text of every candidate file is in
[`attempts.ndjson`](attempts.ndjson) (one JSON line per attempt, with its SHA-256).

| # | UTC | Engine result | Warnings | Author's note |
| --- | --- | --- | --- | --- |
| 1 | 2026-11-11T20:06:53Z | Refused: `annotation.anchor.hidden.lCoil` at `lCoil` | `annotation.cut.lBell`, `annotation.anchor.hidden.lStator`, `annotation.anchor.hidden.lBearing`, `annotation.arrow.hidden.tBack`, `framing.subject.small.step.2`, `framing.subject.small.step.3`, `framing.subject.small.step.4` | first full draft |
| 2 | 2026-11-11T20:08:51Z | Refused: `step.hide.fact` at `count.magN` | none | repair after refusal and first look: label anchors on visible faces, explicit focus lists, bell hidden in top views, cut-away magnets hidden with the cut |
| 3 | 2026-11-11T20:09:13Z | Refused: `annotation.anchor.hidden.lMag` at `lMag` | `annotation.anchor.hidden.lBearing`, `framing.subject.small.step.3` | repair of step.hide.fact: the magnet count moves to a step that hides no magnet |
| 4 | 2026-11-11T20:09:25Z | **Accepted** | none | repair: two engine-suggested label anchors; thicker shaft; step 3 focus without the wires |
| 5 | 2026-11-11T20:10:37Z | **Accepted** | none | visual pass: the shaft joins the focus so the title band does not cut it |
| 6 | 2026-11-11T22:33:30Z | **Accepted** | none | fact-check fixes (Sol + Gemini, merged 2026-11-11), applied by Claude Opus 5.5: caption and label words only; engine build 21b76c20 (same source as ca22181, other build path) |

Total: **6 attempts, 3 refused, 3 accepted**. The published file is attempt 6
(SHA-256 `9ad66aab88e16ab788e35aaf5a242cb15c75ab54517f795ce98760ac4a28f961`).

## Engine verification of the published file

`marty-solid check --strict motor.json`: exit 0, `ok` true, warnings: none. Legend: "Solved 5 (1 animation ratio)".
The full output is [`check-strict.json`](check-strict.json).

## Render

```text
marty-solid render motor.json <NEW_DIR> --size 1280x800 --loop-fps 30 --story-fps 30
```

One render of the published file (the fact-fix render; it replaced the story video and the stills whose words changed: step-5.jpg, step-7.jpg, step-8.jpg); the other stills differ from it only by render noise and are kept from the first render. The story video has 11 beats, 2726 frames, 90.9 seconds, no camera cut.
The engine's `story.mp4` is 33,405,283 bytes. The file here is a re-encode for size
(7,223,465 bytes, H.264, 650,000 bit/s, every frame kept, fast start). The stills are the engine's PNG files
converted to JPEG (quality 0.85). Hashes of the originals and of every file here are in
[`../provenance.json`](../provenance.json).
