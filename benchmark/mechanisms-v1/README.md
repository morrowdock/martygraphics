# Benchmark mechanisms-v1 (pre-registration)

**Status: pre-registered on 2026-11-11. Not run. No result yet.**

This folder fixes, before any run, how MartyGraphics will be compared with direct three.js code on 20 mechanism
questions. The owner decided on 2026-11-11 to run this benchmark blind, to count every run, and to publish the result
whether it is good or bad. An engine feature freeze is active until the result exists.

## The design in short

- **20 questions** in plain learner language: gear trains, a planetary set, a worm drive, rack-and-pinion steering,
  four-bar and crank-slider linkages, cams, a Geneva drive, differentials, a four-stroke engine, turbines, a turbofan
  and two pumps.
- **Arm 1:** Claude Opus 5.5 answers through Marty and the MartyGraphics engine (JSON → engine check → up to 3 repairs
  from the engine's exact reasons → render).
- **Arm 2:** the same model writes one three.js HTML file, with a headless render and up to 3 repairs from console
  errors and screenshots.
- **3 runs** per question per arm (120 runs). Every run counts; a failure scores zero.
- **The same artifact set** for both arms: a 20 s video at 1280 × 800 and 5 stills at fixed times.
- **Blind grading** by two graders from other model families (GPT-6.1 Sol, Gemini 4 Argon) with random A/B labels.
  The seed's hash is committed before grading; the seed is published after it. The stricter grade wins.
- **Primary metric:** mechanism correctness (five checks per question). **Primary test:** a sign test over the 20
  questions. The verdict is win, loss or no conclusion.

## Files

| File | Content |
| --- | --- |
| [QUESTIONS.json](QUESTIONS.json) | The 20 questions with ids and categories, key facts with sources, five mechanism checks per question, the questions excluded because they are shipped examples, and the source list. |
| [RUBRIC.md](RUBRIC.md) | The grader's scorecard: (a) mechanism correctness, (b) text errors and coverage, (c) teaching clarity, (d) visual defects, (e) pairwise preference, with definitions and anchors. |
| [PROTOCOL.md](PROTOCOL.md) | Models, the exact prompts of both arms, runs and failures, the artifact set, blinding, graders, merging, the analysis plan, the stopping rule, the verdict rules and amendments. |
| [HASHES.txt](HASHES.txt) | SHA-256 of the four files above. |

Check the hashes from this folder:

```
shasum -a 256 -c HASHES.txt
```

## What happens next

1. **Fact-check gate:** two independent web fact checks of every key fact (GPT-6.1 Sol, and Gemini 4 Argon without the
   designer's sources). Corrections go in a dated amendment with new hashes.
2. **Harness** pull request (run arms, normalise, mask, blind, grade, analyse), a dry run on a question outside the set,
   and `LOCK.json` with every version and hash.
3. **All 120 runs**, then blinding, then grading, then the analysis exactly as [PROTOCOL.md](PROTOCOL.md) says.
4. **Result** in `results/` in this folder, published whatever it is.

## Honest limits

Full blinding is not possible: the render styles differ. The protocol masks engine footers and legends in both arms and
measures how often graders can tell the arms apart. Some questions are near shipped examples, which can favour Arm 1;
QUESTIONS.json marks them (`nearShipped`). With 20 questions, only a large difference can give a clear verdict. See
[PROTOCOL.md, section 14](PROTOCOL.md#14-residual-risks-and-known-limits).

## Key-fact status

The key facts are **proposed**. Each has a check label: `verified-web` (a web source seen on 2026-11-11 states it),
`textbook-only` (a standard textbook fact with no web source found yet) or `derived` (arithmetic shown in the note).
The textbook citations name the standard reference by chapter topic; the designer did not re-read the books for this
pre-registration. The fact-check gate must confirm or correct every fact and citation before run 1.
