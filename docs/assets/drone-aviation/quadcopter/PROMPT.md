# The brief and every attempt: quadcopter steering

**Hand-built.** A Claude agent (Claude Fable 5.2) wrote [`quadcopter.json`](quadcopter.json) by hand for this question:
"How does a quadcopter steer with four fixed propellers?" It is not the output of Marty's question-to-lesson loop. The MartyGraphics engine at main
`ca2218131e897f1138fa80c0cf23cf21cd23fa4d` checked every attempt (`marty-solid check --strict`, release build) and
rendered the accepted file. Nobody changed a rendered frame.

**Fact-check fixes.** Attempt 11 is by Claude Opus 5.5. It applies the merged fixes of two independent fact
checks (Sol and Gemini, 2026-11-11; see [`../FACTS.md`](../FACTS.md)) to caption and label words only. It was
checked and rendered with a second release build of the same engine source (executable SHA-256
`21b76c201f144fd2d618d89e84cc3b8ccc4d275c316bb9960ed78f6669e6bc40`; the first build's SHA-256 differs. The second build ran in another build directory, and its reports for the
first-round documents are the same as the first build's, minus the engine identity).

## The brief (exact, written before attempt 1)

```text
Explainer brief: quadcopter steering (written before the first attempt, 2026-11-11)

Question: "How does a quadcopter steer with four fixed propellers?"

Show, with the existing MartyGraphics solid engine at main (no engine change):

1. A quadcopter in the X layout: a rigid frame, four motors, one fixed-pitch propeller on each motor.
2. The spin directions, seen from above, in the ArduPilot "Quad X" motor order: M1 front right and M2 rear left turn
   counter-clockwise; M3 front left and M4 rear right turn clockwise. Each pair sits on one diagonal.
3. Why two directions: each motor's reaction torque on the frame is opposite to its propeller's spin, so the four
   torques cancel in hover.
4. Hover: the four thrusts together balance the weight.
5. Roll and pitch come from thrust differences (one side faster, the other side slower). The tilted frame then has a
   sideways part of thrust.
6. Yaw comes from the torque difference: speed up one diagonal pair, slow the other; the total thrust stays the same.
7. A last step that says what the engine checked and what it did not.

Rules I set for myself:

* The engine must solve or check every propeller's turn direction (turn arrows with a stated sense, and checks on the
  speed signs) and the weight direction (a gravity arrow).
* Thrust arrows, poses and all aerodynamics are authored, not computed. Say so in the lesson.
* No typed numbers in captions (rule N1). Motor names M1 to M4 are declared names.
* Blades must lead with the correct edge for their spin direction (a clockwise propeller is the mirror image of a
  counter-clockwise one).
* Count every `marty-solid check --strict` run as one attempt. Keep refused attempts.
```

## Every attempt

One attempt is one run of `marty-solid check --strict` on a candidate file. All attempts count. No attempt was
dropped or run again under the same number. The full text of every candidate file is in
[`attempts.ndjson`](attempts.ndjson) (one JSON line per attempt, with its SHA-256).

| # | UTC | Engine result | Warnings | Author's note |
| --- | --- | --- | --- | --- |
| 1 | 2026-11-11T19:51:37Z | **Accepted** | `framing.subject.small.step.2`, `framing.subject.small.step.3` | first geometry draft: 3 steps only, to see the model |
| 2 | 2026-11-11T19:54:49Z | Refused: `annotation.unused.s2` at `s2` | `annotation.anchor.hidden.lTwistA`, `annotation.anchor.hidden.lTwistB`, `annotation.arrow.dropped.w`, `annotation.arrow.caption.w`, `framing.subject.small.step.2`, `framing.subject.small.step.3`, `framing.subject.small.step.4`, `framing.subject.small.step.5`, `framing.subject.small.step.6`, `framing.subject.small.step.7`, `framing.subject.small.step.8`, `framing.subject.small.step.9`, `unit.small.cg` | full lesson draft: pad, CG marker, tube arms, 10 steps, poses |
| 3 | 2026-11-11T19:56:43Z | Refused: `annotation.anchor.hidden.lTwist` at `lTwist` | `annotation.arrow.hidden.w`, `framing.subject.small.step.2`, `framing.subject.small.step.3`, `framing.subject.small.step.6`, `framing.subject.small.step.7`, `framing.subject.small.step.8`, `framing.subject.small.step.9` | repair of the refusal: removed unused arrow s2; thin ground marking; weight from centre of mass; thrust arrows ride the frame |
| 4 | 2026-11-11T19:57:22Z | Refused: `annotation.anchor.hidden.lMotor` at `lMotor` | `annotation.anchor.hidden.lTwist`, `framing.subject.small.step.2`, `framing.subject.small.step.6`, `framing.subject.small.step.7`, `framing.subject.small.step.8`, `framing.subject.small.step.9` | repair: label anchor clear of the propeller; low camera for the weight arrow; shorter arrows; smaller explode |
| 5 | 2026-11-11T19:58:00Z | Refused: `annotation.anchor.hidden.lTwist` at `lTwist` | `framing.subject.small.step.2`, `framing.subject.small.step.6`, `framing.subject.small.step.8`, `framing.subject.small.step.9` | repair: engine-suggested anchor for lTwist; motor label on the windings; ground nearer; larger ESC and GPS |
| 6 | 2026-11-11T19:58:15Z | **Accepted** | `framing.subject.small.step.2`, `framing.subject.small.step.9` | repair: second engine-suggested anchor for lTwist; small size changes for the subject floors |
| 7 | 2026-11-11T19:59:44Z | **Accepted** | `framing.subject.small.step.2` | visual pass after the first render: step 2 focus list, step 9 camera so the blades are not end-on |
| 8 | 2026-11-11T19:59:58Z | Refused: `annotation.anchor.hidden.lBatt` at `lBatt` | none | step 2 becomes a close-up of the electronics (the exploded view had small labelled parts) |
| 9 | 2026-11-11T20:00:05Z | **Accepted** | none | repair: engine-suggested anchor for the battery label |
| 10 | 2026-11-11T20:34:56Z | **Accepted** | none | fact pass: step 1 speaks about this quadcopter only; step 9 says the total thrust stays about the same |
| 11 | 2026-11-11T22:33:29Z | **Accepted** | none | fact-check fixes (Sol + Gemini, merged 2026-11-11), applied by Claude Opus 5.5: caption and label words only; engine build 21b76c20 (same source as ca22181, other build path) |

Total: **11 attempts, 5 refused, 6 accepted**. The published file is attempt 11
(SHA-256 `129cda759420dba6b549c6f27a9bca0a569256aeca78175e74330d7164108d33`).

## Engine verification of the published file

`marty-solid check --strict quadcopter.json`: exit 0, `ok` true, warnings: none. Legend: "Solved 17 (4 animation ratios) · Not checked 13".
The full output is [`check-strict.json`](check-strict.json).

## Render

```text
marty-solid render quadcopter.json <NEW_DIR> --size 1280x800 --loop-fps 30 --story-fps 30
```

One render of the published file (the fact-fix render; it replaced the story video and the stills whose words changed: step-4.jpg, step-5.jpg, step-9.jpg, step-10.jpg); the other stills differ from it only by render noise and are kept from the first render. The story video has 10 beats, 2612 frames, 87.1 seconds, 2 camera cut(s) (beat 4, 5): the engine cut because the straight and routed camera moves met the swept box of a turning part (`prop1`).
The engine's `story.mp4` is 48,861,731 bytes. The file here is a re-encode for size
(7,069,037 bytes, H.264, 650,000 bit/s, every frame kept, fast start). The stills are the engine's PNG files
converted to JPEG (quality 0.85). Hashes of the originals and of every file here are in
[`../provenance.json`](../provenance.json).
