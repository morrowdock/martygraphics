# The brief and every attempt: payload position and centre of gravity

**Hand-built.** A Claude agent (Claude Fable 5.2) wrote [`payload-cg.json`](payload-cg.json) by hand for this question:
"What happens when a quadcopter's payload sits forward or aft of the centre, and what must the flight controller do?" It is not the output of Marty's question-to-lesson loop. The MartyGraphics engine at main
`ca2218131e897f1138fa80c0cf23cf21cd23fa4d` checked every attempt (`marty-solid check --strict`, release build) and
rendered the accepted file. Nobody changed a rendered frame.

**Fact-check fixes.** Attempt 5 is by Claude Opus 5.5. It applies the merged fixes of two independent fact
checks (Sol and Gemini, 2026-11-11; see [`../FACTS.md`](../FACTS.md)) to caption and label words only. It was
checked and rendered with a second release build of the same engine source (executable SHA-256
`21b76c201f144fd2d618d89e84cc3b8ccc4d275c316bb9960ed78f6669e6bc40`; the first build's SHA-256 differs. The second build ran in another build directory, and its reports for the
first-round documents are the same as the first build's, minus the engine identity).

## The brief (exact, written before attempt 1)

```text
Explainer brief: payload position and centre of gravity (written before the first attempt, 2026-11-11)

Question: "What happens when a quadcopter's payload sits forward or aft of the centre, and what must the flight
controller do?"

For a learner who studies for the FAA Part 107 knowledge test (loading and centre of gravity). No regulation
claims in the scene.

Show, with the existing MartyGraphics solid engine at main (no engine change):

1. The quadcopter of the steering explainer with a payload on a rail under the frame.
2. Payload in the middle: the weight acts close to the centre of the four propellers; four equal thrusts hold the
   drone level.
3. Payload moved forward: the centre of gravity moves forward. With four equal thrusts, the total thrust acts at
   the centre of the propellers, so the weight ahead of it turns the nose down.
4. What the flight controller does: it speeds up the front motors and slows the rear motors until the total
   thrust acts above the weight. The front motors then work harder for the whole flight and have less reserve.
5. Payload aft: the opposite.
6. Payload too far from the centre: the motors on that side reach full power and the controller cannot hold the
   drone level.
7. A last step that says what the engine computed and what it did not.

Rules I set for myself:

* The engine must compute where the weight acts: the gravity arrow starts at the engine's `centreOfMass` anchor,
  which the engine works out again at every pose. Say that it is the centre of the drawn shapes with one density
  for all parts (a schematic centre of gravity), not a weighed aircraft.
* Known engine limit: a pose can turn a part but cannot slide it (`step.pose.key`). So the payload part turns by a
  small angle about a pivot far above the drone; its path along the rail is then straight within about 1 mm. Say
  this in the notes.
* Thrust arrows and tilts are authored. No flight is simulated. No typed numbers in captions (rule N1).
* Count every `marty-solid check --strict` run as one attempt. Keep refused attempts.
```

## Every attempt

One attempt is one run of `marty-solid check --strict` on a candidate file. All attempts count. No attempt was
dropped or run again under the same number. The full text of every candidate file is in
[`attempts.ndjson`](attempts.ndjson) (one JSON line per attempt, with its SHA-256).

| # | UTC | Engine result | Warnings | Author's note |
| --- | --- | --- | --- | --- |
| 1 | 2026-11-11T21:28:13Z | Refused: `annotation.anchor.hidden.lRail` at `lRail` | `annotation.anchor.hidden.lFront`, `annotation.arrow.hidden.w`, `annotation.arrow.hidden.w`, `annotation.arrow.hidden.w`, `annotation.arrow.hidden.w`, `annotation.arrow.hidden.w`, `annotation.arrow.hidden.w`, `framing.subject.small.step.1`, `framing.subject.small.step.3`, `framing.subject.small.step.5`, `framing.subject.small.step.7` | first full draft (parts of the steering quadcopter, plus a rail and a payload) |
| 2 | 2026-11-11T21:28:30Z | **Accepted** | `framing.subject.small.step.3`, `framing.subject.small.step.5`, `framing.subject.small.step.7` | repair: engine-suggested rail anchor; no Front label (the camera is small); shorter weight arrow so that its head stays above the ground |
| 3 | 2026-11-11T21:29:11Z | **Accepted** | none | render review: the engine made the frame a ghost in the posed steps (the moved payload was the subject); explicit focus on frame and payload; larger payload and longer travel so that the shift can be seen |
| 4 | 2026-11-11T21:29:40Z | **Accepted** | none | render review: step 1 was a close-up that cut the drone; it now frames the whole frame and payload |
| 5 | 2026-11-11T22:33:31Z | **Accepted** | none | fact-check fixes (Sol + Gemini, merged 2026-11-11), applied by Claude Opus 5.5: caption and label words only; engine build 21b76c20 (same source as ca22181, other build path) |

Total: **5 attempts, 1 refused, 4 accepted**. The published file is attempt 5
(SHA-256 `37659f53103ec6413428ffa600e453a2eaab8639f26ef9eacbdf795026b748ed`).

## Engine verification of the published file

`marty-solid check --strict payload-cg.json`: exit 0, `ok` true, warnings: none. Legend: "Solved 5 (4 animation ratios) · Not checked 16".
The full output is [`check-strict.json`](check-strict.json).

## Render

```text
marty-solid render payload-cg.json <NEW_DIR> --size 1280x800 --loop-fps 30 --story-fps 30
```

One render of the published file (the fact-fix render; it replaced the story video and the stills whose words changed: step-2.jpg, step-5.jpg, step-6.jpg, step-8.jpg, step-9.jpg, poster.jpg); the other stills differ from it only by render noise and are kept from the first render. The story video has 9 beats, 2422 frames, 80.7 seconds, no camera cut.
The engine's `story.mp4` is 40,009,147 bytes. The file here is a re-encode for size
(6,551,444 bytes, H.264, 650,000 bit/s, every frame kept, fast start). The stills are the engine's PNG files
converted to JPEG (quality 0.85). Hashes of the originals and of every file here are in
[`../provenance.json`](../provenance.json).
