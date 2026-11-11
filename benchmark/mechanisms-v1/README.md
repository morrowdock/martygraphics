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
- **Locked inputs:** Marty `0593bcd`, the engine it pins (`38f3863`), Marty's prompt file, three.js r170 and every
  prompt file here, by hash. No engine, Marty or prompt change applies after registration.
- **3 runs** per question per arm (120 runs). Every run counts; a failure scores zero.
- **The same evidence** for both arms and both graders: 5 stills, a 10 fps frame strip in labelled contact sheets, and
  the OCR text. The strip's adequacy is validated on synthetic motion ([validation/](validation/README.md)).
- **Grading:** every rendered output is scored alone in an anonymous packet, by GPT-6.1 Sol and Gemini 4 Argon. Pairs
  with two rendered outputs also get a preference call. A grader may answer CANNOT JUDGE for direction or timing;
  otherwise the stricter grade wins.
- **Verdict:** a question-level sign test on the mechanism score: win, loss or no conclusion. Everything else is
  exploratory and can never be a route to a win.

## Files

| File | Content |
| --- | --- |
| [QUESTIONS.json](QUESTIONS.json) | The 20 questions with ids and categories, key facts with sources, accepted variants and designer notes, five mechanism checks per question, the excluded questions and the source list. |
| [GRADER-QUESTIONS.json](GRADER-QUESTIONS.json) | The graders' view: only the question text, the key facts with accepted variants, and the checks. Made by [tools/grader_questions.py](tools/grader_questions.py). |
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

1. The merged corrections from two independent fact checks (GPT-6.1 Sol with sources, Gemini 4 Argon blind).
2. The grader validation on the synthetic packets (pending: no grader access on the designer's host).
3. A refresh of LOCK.json if a locked main moves.

## After registration

1. A harness pull request, `RUN-LOCK.json` and a dry run on a question outside the set.
2. All 120 runs, then masking and packing, then grading, then the analysis exactly as [PROTOCOL.md](PROTOCOL.md) says.
3. The result in `results/` in this folder, with all generation and grading evidence, published whatever it is.

## Honest limits

See [PROTOCOL.md, section 14](PROTOCOL.md#14-residual-risks-and-known-limits): partial blinding (render style and the
kept limitation labels can reveal the arm), five questions near shipped examples (a descriptive sensitivity analysis
leaves them out), an engine 5 commits behind main, and low power with 20 questions.

## Key-fact status

The key facts are **proposed**. Each has a check label: `verified-web` (a web source seen on 2026-11-11 states it),
`textbook-only` (a standard textbook fact with no web source found yet) or `derived` (arithmetic shown in the designer note).
The textbook citations name the standard reference by chapter topic; the designer did not re-read the books. The
fact-check gate confirms or corrects every fact and citation before registration closes.
