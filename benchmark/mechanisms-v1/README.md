# Benchmark mechanisms-v1 (pre-registration)

**Status: pre-registration. Not run. No result yet.** Registration closes when the pull request that adds this folder
merges; the inputs in [LOCK.json](LOCK.json) are locked at that moment.

This folder fixes, before any run, how two routes are compared on 20 mechanism questions. It is a
**research-disabled product-route comparison** with **partial blinding**. The owner decided on 2026-11-11 to count
every run and to publish the result whether it is good or bad.

## The design in short

- **20 questions** in plain learner language: gear trains, a planetary set, a worm drive, rack-and-pinion steering,
  four-bar and crank-slider linkages, cams, a Geneva drive, differentials, four-stroke engines, turbines, a turbofan
  and pumps.
- **Arm 1:** Claude Opus 5.5 answers through Marty and the MartyGraphics engine (JSON → engine check → up to 3 repairs
  from the engine's exact reasons → render).
- **Arm 2:** the same model writes one three.js HTML file, with a headless render and up to 3 repairs from console
  errors and screenshots.
- **Equal maximum repair counts, different route-specific assistance.** Research is off in both arms.
- **Locked inputs:** Marty `1f27295`, the engine it pins (`38f3863`), Marty's prompt file, three.js r170 and every
  prompt file here, by hash. No engine, Marty or prompt change applies after registration.
- **3 runs** per question per arm (120 runs). Every run counts; a failure scores zero.
- **The same evidence** for both arms and both graders: 5 stills, a 10 fps frame strip in labelled contact sheets, and
  the OCR text. The strip's adequacy is validated on synthetic motion, objectively and with both graders
  ([validation/](validation/README.md)).
- **Grading:** every rendered output is scored alone in an anonymous packet, by GPT-6.1 Sol and Gemini 4 Argon. Pairs
  with two rendered outputs also get a preference call. A grader may answer CANNOT JUDGE for direction or timing;
  otherwise the stricter grade wins.
- **Verdict:** a question-level sign test on the mechanism score: win, loss or no conclusion. Everything else is
  exploratory and can never be a route to a win.

## Files

| File | Content |
| --- | --- |
| [QUESTIONS.json](QUESTIONS.json) | Key version 2: the 20 questions with ids and categories, the conventional configuration and accepted variants, key facts with sources, `appliesTo`, accepted wordings, designer notes and fact-check records, five mechanism checks per question, the excluded questions and the source list. |
| [FACTCHECK.md](FACTCHECK.md) | The receipt of the two independent fact checks and every action taken. |
| [GRADER-QUESTIONS.json](GRADER-QUESTIONS.json) | The graders' view: only the question text, the configurations, the key facts with `appliesTo` and accepted wordings, and the checks. Made by [tools/grader_questions.py](tools/grader_questions.py). |
| [RUBRIC.md](RUBRIC.md) | The scorecard: (a) mechanism correctness, (b) text errors and coverage, (c) teaching clarity, (d) visual defects, (e) pairwise preference. |
| [PROTOCOL.md](PROTOCOL.md) | The lock and the gates, models, both arms, runs and failures, the evidence, partial blinding, graders, merging, the analysis plan, verdict, publication and amendments. |
| [LOCK.json](LOCK.json) | The locked inputs (commits, prompt file hashes, three.js hashes, models, seeds). |
| [prompts/](prompts/ARM2-SYSTEM.txt) | The Arm 2 system and repair prompts and the three grader prompts. |
| [validation/](validation/README.md) | The temporal evidence validation: script, results and grader packets. |
| [HASHES.txt](HASHES.txt) | SHA-256 of every other file in this folder. |

Check the hashes from this folder:

```
shasum -a 256 -c HASHES.txt
```

## Before registration closes

1. A refresh of LOCK.json if a locked main moves.

Done: the fact-check gate (key version 2, [FACTCHECK.md](FACTCHECK.md)) and the grader validation on the synthetic
packets (both graders pass, [validation/](validation/README.md)).

## After registration

1. A harness pull request, `RUN-LOCK.json` and a dry run on a question outside the set.
2. All 120 runs, then masking and packing, then grading, then the analysis exactly as [PROTOCOL.md](PROTOCOL.md) says.
3. The result in `results/` in this folder, with all generation and grading evidence, published whatever it is.

## Honest limits

See [PROTOCOL.md, section 14](PROTOCOL.md#14-residual-risks-and-known-limits): partial blinding (render style and the
kept limitation labels can reveal the arm), five questions near shipped examples (a descriptive sensitivity analysis
leaves them out), an engine 7 commits behind main, and low power with 20 questions.

## Key-fact status

The key is **version 2**, after two independent fact checks ([FACTCHECK.md](FACTCHECK.md)). Each fact has a check
label (`verified-web`, `single-source`, `textbook-only`, `fact-check-only` or `derived`) and a record of both fact-check
labels and the action taken. Textbook citations name the reference by chapter topic; page-level verification is an
open item, except Norton section 9.8 and Uicker section 8.15.
