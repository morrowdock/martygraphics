# Temporal evidence validation (mechanisms-v1)

Status: **objective validation done (2026-11-11), all in-scope cases pass. Grader validation: pending** (required
before registration closes; see [PROTOCOL.md, section 2.3](../PROTOCOL.md#23-temporal-evidence-gate-before-the-merge)).

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
answer key (`packets/KEY.json`, with the pass rule and tolerances). Each primary grader (GPT-6.1 Sol, Gemini 4 Argon)
answers every packet in a new session that holds only that packet's sheets. The raw replies and the scores go in
`graders/`. Pass rule: at least 90 % of the in-scope packets correct, and no wrong direction on an in-scope rotation
packet.

**Pending.** On 2026-11-11 the designer's host had no working grader access (the Codex CLI was not logged in; the
Gemini CLI was not installed). The grader validation must run where both graders are available, and its results must
be committed before registration closes.

## Limits

- Synthetic shapes are simpler than real renders: high contrast, no shading, no occlusion. The strip's information is
  validated; the graders' ability to use it on real renders is tested by the grader validation and measured during
  grading by the CANNOT JUDGE counts.
- The analyser tracks one known feature per part. A grader must find such a feature itself; the rubric tells it how.
