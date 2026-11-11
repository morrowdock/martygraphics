# Drone and aviation explainers (hand-built)

Five explainers made with the solid engine at main `ca2218131e897f1138fa80c0cf23cf21cd23fa4d`, with no engine
change. A Claude agent (Claude Fable 5.2) wrote each document by hand from a short brief. The engine checked every
attempt and rendered the accepted file. **Two independent fact checks (Sol and Gemini, 2026-11-11) found no wrong
claim; Claude Opus 5.5 applied all 16 fixes (one more counted attempt for each document, then a new render of the
story videos and of the stills whose words changed): see [FACTS.md](FACTS.md).**

| Explainer | Document | Attempts | Engine result | Story video | Engine checked |
| --- | --- | --- | --- | --- | --- |
| [Quadcopter steering](quadcopter/PROMPT.md) | [quadcopter.json](quadcopter/quadcopter.json) (152 lines, 21 parts, 10 steps) | 11: 5 refused, 6 accepted | Refusal, then repair: `annotation.unused.s2`, then four hidden label anchors (`annotation.anchor.hidden.<id>`); three were repaired with the engine's own suggested anchors | [story.mp4](quadcopter/story.mp4), 87 s, 10 beats · [loop.mp4](quadcopter/loop.mp4) | The turn direction of each propeller (4 turn arrows, 8 checks) and the weight direction |
| [Brushless outrunner motor](brushless-motor/PROMPT.md) | [motor.json](brushless-motor/motor.json) (68 lines, 32 parts, 11 steps) | 6: 3 refused, 3 accepted | Refusal, then repair: `annotation.anchor.hidden.lCoil`, `step.hide.fact` (a caption gave the magnet count while its step hid magnets), `annotation.anchor.hidden.lMag` | [story.mp4](brushless-motor/story.mp4), 91 s, 11 beats · [loop.mp4](brushless-motor/loop.mp4) | The bell's rotation and the counts: 12 coils, 7 + 7 magnets |
| [Three-axis camera gimbal](gimbal/PROMPT.md) | [gimbal.json](gimbal/gimbal.json) (103 lines, 15 parts, 8 steps) | 6: 1 refused (a deliberate negative control), 5 accepted | Accepted at attempt 1 with one warning (`frame.child.far.drone`), cleared in attempt 3. The negative control was refused with `step.pose.fact` | [story.mp4](gimbal/story.mp4), 70 s, 8 beats | At four poses, two measured dimensions on the camera keep their values: the camera is level |
| [Landing gear over-centre lock](landing-gear/PROMPT.md) | [landing-gear.json](landing-gear/landing-gear.json) (80 lines, 11 parts, 11 steps) | 11: 4 refused (1 a deliberate negative control), 7 accepted | Refusal, then repair: `step.say` (caption 9 characters too long), two hidden label anchors; the negative control was refused with `step.pose.fact` | [story.mp4](landing-gear/story.mp4), 78 s, 11 beats | At the rest pose and six poses, the two pin-to-leg distances keep their values (they do not alone prove the pin is in its hole; GAPS.md, gap 14) |
| [Payload position and centre of gravity](payload-cg/PROMPT.md) | [payload-cg.json](payload-cg/payload-cg.json) (143 lines, 23 parts, 9 steps) | 5: 1 refused, 4 accepted | Refusal, then repair: `annotation.anchor.hidden.lRail` (repaired with the engine's suggested anchor) | [story.mp4](payload-cg/story.mp4), 81 s, 9 beats | Where the weight arrow starts: the engine's volume centre of all drawn parts (not the aircraft CG), worked out again at each payload position; the weight direction |

All five published files pass `marty-solid check --strict` with no warning (each folder's `check-strict.json`).
In all: 39 attempts, 14 refused (2 of them deliberate negative controls), 25 accepted. The last attempt of each
document is the fact-check fix.

Two of the five serve a learner who studies for a remote pilot knowledge test: quadcopter steering (yaw, roll and
pitch from speed and torque differences) and payload position and centre of gravity. Neither makes a regulation
claim.

* [FACTS.md](FACTS.md): every claim, why it is true, a public source, and what the engine did with it.
* [GAPS.md](GAPS.md): what the frozen engine could not show, with exact refusal texts. The helicopter swashplate
  topic was dropped for these gaps.
* [provenance.json](provenance.json): the engine build, the commands, and the SHA-256 of every file.

Each folder holds the document, `PROMPT.md` (the exact brief and the attempt list), `attempts.ndjson` (the full
text of every attempt), `check-strict.json`, `story.mp4`, `poster.jpg`, `hero.jpg`, `exploded.jpg` and one
`step-<n>.jpg` for each step. The videos are re-encodes of the engine's files for size (H.264, fast start, every
frame kept); the stills are the engine's PNG files as JPEG. No frame was edited.
