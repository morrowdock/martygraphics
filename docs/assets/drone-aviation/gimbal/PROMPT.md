# The brief and every attempt: three-axis camera gimbal

**Hand-built.** A Claude agent (Claude Fable 5.2) wrote [`gimbal.json`](gimbal.json) by hand for this question:
"How does a drone's three-axis gimbal keep the camera steady?" It is not the output of Marty's question-to-lesson loop. The MartyGraphics engine at main
`ca2218131e897f1138fa80c0cf23cf21cd23fa4d` checked every attempt (`marty-solid check --strict`, release build) and
rendered the accepted file. Nobody changed a rendered frame.

**Fact-check fixes.** Attempt 6 is by Claude Opus 5.5. It applies the merged fixes of two independent fact
checks (Sol and Gemini, 2026-11-11; see [`../FACTS.md`](../FACTS.md)) to caption and label words only. It was
checked and rendered with a second release build of the same engine source (executable SHA-256
`21b76c201f144fd2d618d89e84cc3b8ccc4d275c316bb9960ed78f6669e6bc40`; the first build's SHA-256 differs. The second build ran in another build directory, and its reports for the
first-round documents are the same as the first build's, minus the engine identity).

## The brief (exact, written before attempt 1)

```text
Explainer brief: three-axis camera gimbal (written before the first attempt, 2026-11-11)

Question: "How does a drone's three-axis gimbal keep the camera steady?"

Show, with the existing MartyGraphics solid engine at main (no engine change):

1. A camera on three motor axes in the usual order from the drone: yaw, then roll, then pitch. The three axes meet
   at the camera.
2. The drone body pitches, rolls and yaws; each motor turns its arm the other way by the same angle; the camera keeps
   its direction.
3. One step for each axis alone (yaw, roll, pitch), then all three together.
4. A motion sensor (IMU) on the camera measures the camera's turn; the controller drives the motors to cancel it.
5. Limits: a gimbal holds direction only. It does not remove movement up, down or sideways.

Rules I set for myself:

* The motion is kinematic only. The drone body's turn is an authored input; each gimbal joint follows it with ratio -1
  (`follow`). The engine labels this motion "Schematic". Say that the control loop is not modelled.
* The engine must CHECK that the camera is level in every posed step: two measured dimensions on the camera (lens
  axis along world Y, camera top along world Z) must keep their values at each pose (`check`, rule step.pose.fact).
* Run one deliberate negative control: a pose in which one motor does not cancel the drone's turn must be refused.
  Label it as a negative control in the attempt list.
* The drone body turns about the camera's centre in this model, so the camera also stays in place. Say so: a real
  gimbal does not remove translation.
* No typed numbers in captions (rule N1).
* Count every `marty-solid check --strict` run as one attempt. Keep refused attempts.
```

## Every attempt

One attempt is one run of `marty-solid check --strict` on a candidate file. All attempts count. No attempt was
dropped or run again under the same number. The full text of every candidate file is in
[`attempts.ndjson`](attempts.ndjson) (one JSON line per attempt, with its SHA-256).

| # | UTC | Engine result | Warnings | Author's note |
| --- | --- | --- | --- | --- |
| 1 | 2026-11-11T20:16:41Z | **Accepted** | `frame.child.far.drone` | first full draft |
| 2 | 2026-11-11T20:17:23Z | Refused: `step.pose.fact` at `dim.fwd` | none | DELIBERATE NEGATIVE CONTROL: in step 3 the yaw motor does not cancel the drone's yaw; the engine must refuse the level check |
| 3 | 2026-11-11T20:17:23Z | **Accepted** | `framing.subject.small.step.7` | larger hidden pivots and a yaw pin (clears frame.child.far); wide steps frame the whole drone |
| 4 | 2026-11-11T20:17:37Z | **Accepted** | none | step 7 focus without the two rear propellers (they were small behind the motors) |
| 5 | 2026-11-11T21:06:35Z | **Accepted** | none | render review: the close-up steps did not show the drone body, so its turn could not be seen; steps 3 to 6 now frame the drone body and arms too |
| 6 | 2026-11-11T22:33:30Z | **Accepted** | none | fact-check fixes (Sol + Gemini, merged 2026-11-11), applied by Claude Opus 5.5: caption and label words only; engine build 21b76c20 (same source as ca22181, other build path) |

Total: **6 attempts, 1 refused, 5 accepted** (1 of the refusals is a deliberate negative control). The published file is attempt 6
(SHA-256 `e8912667e2afd3229903e0b2a65a4c20cdb25fcbdcf563b1f0be6abaaeef9605`).

## Engine verification of the published file

`marty-solid check --strict gimbal.json`: exit 0, `ok` true, warnings: none. Legend: "Solved 10 · Schematic 10".
The full output is [`check-strict.json`](check-strict.json).

## Render

```text
marty-solid render gimbal.json <NEW_DIR> --size 1280x800 --loop-fps 30 --story-fps 30
```

One render of the published file (the fact-fix render; it replaced the story video and the stills whose words changed: step-6.jpg, poster.jpg); the other stills differ from it only by render noise and are kept from the first render. The story video has 8 beats, 2114 frames, 70.5 seconds, 1 camera cut(s) (beat 2): the engine cut because the straight and routed camera moves met the swept box of a turning part (`pods`).
The engine's `story.mp4` is 26,440,184 bytes. The file here is a re-encode for size
(5,622,611 bytes, H.264, 650,000 bit/s, every frame kept, fast start). The stills are the engine's PNG files
converted to JPEG (quality 0.85). Hashes of the originals and of every file here are in
[`../provenance.json`](../provenance.json).
