# Temporal evidence validation (mechanisms-v1)

Status: **objective validation done (2026-11-11), all in-scope cases pass. Grader validation done (2026-11-11): both
graders pass** ([PROTOCOL.md, section 2.3](../PROTOCOL.md#23-temporal-evidence-gate-before-the-merge)).

## Why

The primary graders judge motion (direction, ratios, timing, flicker) from a **frame strip**: every 3rd frame of the
30 fps video (10 fps), as 256 × 160 thumbnails (1/5 size) in 5 × 5 contact sheets with the time under each frame. Both
graders get exactly the same strip. This folder tests whether that strip carries the information that the checks
need.

## Method

[temporal_evidence.py](temporal_evidence.py) (Python standard library only, deterministic) renders synthetic
mechanisms at 30 fps, keeps **only** the strip frames, and recovers each answer from those pixels alone (orientation
of dark features by a circular mean; minimal-displacement tracking between strip frames).

```
cd benchmark/mechanisms-v1
python3 -I validation/temporal_evidence.py validation/RESULTS.json validation/packets
```

The run reproduces [RESULTS.json](RESULTS.json) and every packet PNG byte for byte.

The adequacy rule under test: a motion is adequate when a visible feature moves at most 1/4 of its repeat period
between strip frames (4 × sampling).

## Results ([RESULTS.json](RESULTS.json))

| Group | Cases | Result |
| --- | --- | --- |
| V1 rotation direction: one-marker disk at 0.25, 1.0 and 2.5 turn/s, both directions; 4-arm cross at 0.25 and 0.6 turn/s | 8 | 8 correct |
| V2 valve timing: crank at 0.25 and 1.0 turn/s (13° off the sample grid); valve open in the intake half-turn of every second turn | 2 | 2 correct: open and close angles within one strip frame (4.1° and 13.0° error against 9° and 36° per frame); openings counted exactly |
| V3 Geneva dwell: exact external Geneva kinematics, n = 4 and n = 6, driver 0.25 turn/s | 2 | 2 correct: steps 90.0° and 60.0°, motion share 0.252 (true 0.250) and 0.352 (true 0.333), wheel turns opposite to the driver. The n = 4 peak is 21.7° per strip frame against the 22.5° limit |
| V4 flicker: a block missing for 3, 6 or 15 video frames (0.1 s or more), every phase | 9 | 9 seen |

**Controls (reported, not scored):**

| Control | What the strip shows |
| --- | --- |
| One marker at 5 turn/s (180° per strip frame) | cannot judge (every step ambiguous) |
| One marker at 6 turn/s (216° per strip frame) | **WRONG direction** (aliasing) |
| 4-arm cross at 2 turn/s (72° per frame against a 90° repeat) | **WRONG direction** (aliasing) |
| Flicker of 1 or 2 video frames (under 0.1 s) | seen in 3 of 6 phases: not reliable, so out of scope |

The controls show why the protocol has motion limits and a CANNOT JUDGE answer: beyond the 4 × rule, a frame strip
can show a confident wrong direction.

## Grader validation packets ([packets/](packets/KEY.json))

26 packets (21 in scope, 5 controls): the strip sheets of the cases above, a fixed prompt (`packets/PROMPT.txt`) and an
answer key (`packets/KEY.json`, with the pass rule and tolerances). Pass rule: at least 90 % of the in-scope packets
correct, and no wrong direction on an in-scope rotation packet.

## Grader validation results ([graders/](graders/SCORES.json))

Run on 2026-11-11 by the coordinator; committed here as run.

**Method.** The packet folders were renamed P01–P26, because the case names revealed the answers
([MAPPING.json](graders/MAPPING.json); a random order with seed 20261111). One fresh session per grader answered all 26
packets in that order ([ORDER.txt](graders/ORDER.txt)), with no answer key and no feedback. Each grader got only
[PROMPT.txt](graders/PROMPT.txt) (`{case}` replaced by `{packet id}`), the questions without answers
([QUESTIONS.json](graders/QUESTIONS.json)) and the sheets (byte-identical to `packets/`; checked by SHA-256, 83 of 83).

**Deviation from the plan.** The plan was one new session per packet (52 sessions); that was impractical. The packets
are independent synthetic tests and no answer was shown, so one session per grader keeps the test valid.

**Scoring.** [score_grader_validation.py](graders/score_grader_validation.py) scores the raw replies against
`packets/KEY.json`. It scores a Geneva motion share given as a range at the midpoint of the range. The committed copy
adds only an SPDX license line to the original (original SHA-256 in SCORES.json).

| Grader | Model string, tool | In scope correct | Wrong directions (in scope) | Result |
| --- | --- | --- | --- | --- |
| G1 | `gpt-6.1-sol`, Codex, reasoning high | 21 / 21 (100 %) | 0 | **Pass** |
| G2 | `gemini-4-argon`, Antigravity, thinking high | 20 / 21 (95.2 %) | 0 | **Pass** |

G2's miss: the 6-slot Geneva wheel; it gave a motion share of 20–25 % against the true 33 %.

**Controls (reported, not scored):**

| Control | G1 (Sol) | G2 (Gemini) |
| --- | --- | --- |
| One marker at 5 turn/s | cannot judge | cannot judge |
| One marker at 6 turn/s | **clockwise (WRONG, confident)** | **clockwise (WRONG, confident)** |
| 4-arm cross at 2 turn/s | **clockwise (WRONG, confident)** | **clockwise (WRONG, confident)** |
| Flicker of 1 or 2 video frames (not in the strip) | cannot judge | no |

**What this shows.** Inside the motion limits, both graders read direction, valve timing, Geneva steps and flicker
times from the strip. Beyond the limits, both graders gave a confident wrong direction, exactly as the objective
controls predicted. This supports the speed limits in the Arm 2 prompt and the engine's default story speed, and the
CANNOT JUDGE answer for direction and timing. It also shows that a grader does not always notice when motion is too
fast; the per-arm CANNOT JUDGE counts and the limits are the protection, not the grader's caution.

## Limits

- Synthetic shapes are simpler than real renders: high contrast, no shading, no occlusion. Both validations (objective
  and grader) use these synthetic shapes. How well the graders use the strip on real renders is not validated here; it
  is measured during grading by the CANNOT JUDGE counts and the grader agreement.
- The analyser tracks one known feature per part. A grader must find such a feature itself; the rubric tells it how.
