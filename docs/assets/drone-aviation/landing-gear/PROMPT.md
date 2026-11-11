# The brief and every attempt: landing gear over-centre lock

**Hand-built.** A Claude agent (Claude Fable 5.2) wrote [`landing-gear.json`](landing-gear.json) by hand for this question:
"How does a folding side brace lock a retractable landing gear down?" It is not the output of Marty's question-to-lesson loop. The MartyGraphics engine at main
`ca2218131e897f1138fa80c0cf23cf21cd23fa4d` checked every attempt (`marty-solid check --strict`, release build) and
rendered the accepted file. Nobody changed a rendered frame.

**Fact-check fixes.** Attempt 11 is by Claude Opus 5.5. It applies the merged fixes of two independent fact
checks (Sol and Gemini, 2026-11-11; see [`../FACTS.md`](../FACTS.md)) to caption and label words only. It was
checked and rendered with a second release build of the same engine source (executable SHA-256
`21b76c201f144fd2d618d89e84cc3b8ccc4d275c316bb9960ed78f6669e6bc40`; the first build's SHA-256 differs. The second build ran in another build directory, and its reports for the
first-round documents are the same as the first build's, minus the engine identity).

## The brief (exact, written before attempt 1)

```text
Explainer brief: retractable landing gear with an over-centre lock (written before the first attempt, 2026-11-11)

Question: "How does a folding side brace lock a retractable landing gear down?"

Show, with the existing MartyGraphics solid engine at main (no engine change):

1. A main landing gear leg that turns about a trunnion, a two-link folding side brace, and a retract actuator.
2. The over-centre lock: with the gear down, the knee joint of the brace sits a little past the straight line between
   the brace's two end pins and rests on a stop.
3. Why it locks: a load that tries to fold the gear squeezes the brace, and the squeeze pushes the knee harder onto
   its stop.
4. Unlock and retract: the knee is pulled back through the straight line, then the actuator turns the leg up and
   the brace folds.
5. A last step that says what the engine checked and what it did not.

Known engine limit before I start: the engine has no general linkage solver (only gear meshes and the in-line
slider-crank). So this lesson uses step poses. I compute the link angles for each pose outside the engine (a planar
four-bar closure, scratch calculation). The engine must then CHECK each pose:

* Two measured dimensions from the pin at the free end of the lower link to two points of the leg. If both keep their
  values at a pose, the pin is in its hole (rule step.pose.fact refuses a pose where a displayed fact does not hold).
* Run one deliberate negative control: a pose with a wrong link angle must be refused. Label it as a negative control.

Rules I set for myself:

* Say that the video blends the angles between two checked poses and that the engine does not check the blend.
* Loads, the stop contact, the springs and the hydraulics are not modelled. Force arrows are authored.
* The over-centre angle is drawn larger than on a real aircraft, and the lesson says so.
* No typed numbers in captions (rule N1).
* Count every `marty-solid check --strict` run as one attempt. Keep refused attempts.
```

## Every attempt

One attempt is one run of `marty-solid check --strict` on a candidate file. All attempts count. No attempt was
dropped or run again under the same number. The full text of every candidate file is in
[`attempts.ndjson`](attempts.ndjson) (one JSON line per attempt, with its SHA-256).

| # | UTC | Engine result | Warnings | Author's note |
| --- | --- | --- | --- | --- |
| 1 | 2026-11-11T20:23:19Z | Refused: `step.say` | none | first full draft |
| 2 | 2026-11-11T20:23:25Z | Refused: `annotation.anchor.hidden.lTrunnion` at `lTrunnion` | `framing.subject.small.step.1`, `framing.subject.small.step.3`, `framing.subject.small.step.4` | repair of step.say: the last caption is shorter |
| 3 | 2026-11-11T20:23:49Z | Refused: `annotation.anchor.hidden.lTrunnion` at `lTrunnion` | none | repair: engine-suggested anchor for the trunnion label; explicit focus lists; thicker brace links |
| 4 | 2026-11-11T20:24:00Z | **Accepted** | none | repair: the trunnion pin goes through the front lug, and its label sits on the pin end |
| 5 | 2026-11-11T20:24:41Z | Refused: `step.pose.fact` at `dim.pinA` | none | DELIBERATE NEGATIVE CONTROL: in step 8 the upper link angle is 3 degrees wrong, so the pin misses the leg; the engine must refuse it |
| 6 | 2026-11-11T20:24:41Z | **Accepted** | none | visual pass: thicker leg and links, torque links, matte floor, shorter beam |
| 7 | 2026-11-11T20:27:07Z | **Accepted** | none | author error found in the render review: the unlock force arrow pointed away from the folding side; now it points toward the trunnion side (the engine does not check authored force arrows) |
| 8 | 2026-11-11T20:34:57Z | **Accepted** | none | fact pass: the limits step says that real gears add lock links and springs |
| 9 | 2026-11-11T20:59:37Z | **Accepted** | none | build check: the debug and the release engine placed two arrow texts of step 3 on opposite sides in the report's legacy placements (a tie between opposite candidates); the two texts become labels |
| 10 | 2026-11-11T21:02:27Z | **Accepted** | none | render review of attempt 9: the two labels covered the arrows; back to arrow texts, and step 3 now highlights the two brace links (this also removes the placement tie) |
| 11 | 2026-11-11T22:33:30Z | **Accepted** | none | fact-check fixes (Sol + Gemini, merged 2026-11-11), applied by Claude Opus 5.5: caption and label words only; engine build 21b76c20 (same source as ca22181, other build path) |

Total: **11 attempts, 4 refused, 7 accepted** (1 of the refusals is a deliberate negative control). The published file is attempt 11
(SHA-256 `c0c4e14b7de62481846952dd47ba9d03a816100c19950f11d1c5b1ee37d81e2d`).

## Engine verification of the published file

`marty-solid check --strict landing-gear.json`: exit 0, `ok` true, warnings: none. Legend: "Solved 16 · Not checked 5".
The full output is [`check-strict.json`](check-strict.json).

## Render

```text
marty-solid render landing-gear.json <NEW_DIR> --size 1280x800 --loop-fps 30 --story-fps 30
```

One render of the published file (the fact-fix render; it replaced the story video and the stills whose words changed: step-4.jpg, step-5.jpg, step-11.jpg); the other stills differ from it only by render noise and are kept from the first render. The story video has 11 beats, 2326 frames, 77.5 seconds, no camera cut.
The engine's `story.mp4` is 15,180,764 bytes. The file here is a re-encode for size
(5,403,674 bytes, H.264, 650,000 bit/s, every frame kept, fast start). The stills are the engine's PNG files
converted to JPEG (quality 0.85). Hashes of the originals and of every file here are in
[`../provenance.json`](../provenance.json).
