# The prompt, the setup and every try (jet suit, round 2j, run `r2j-opus-1`)

This folder holds an AI-written lesson, shown unedited. An AI model wrote the lesson JSON from one question. The
MartyGraphics engine checked it and rendered it. Nobody changed the JSON or the renders by hand. The errors that an
independent fact check found are listed in [FACT-CHECK.md](FACT-CHECK.md); they are not fixed in the lesson.

## The prompt

| | |
| --- | --- |
| Question (exact) | `How does the Gravity jet suit work?` |
| Follow-up (exact, same run) | `How does the pilot steer?` |
| Command | `marty ask "How does the Gravity jet suit work?" --out runs/r2j-opus-1 --model claude-opus-5-5 --follow-up "How does the pilot steer?" --repairs 3` |
| Model | `claude-cli:claude-opus-5-5` (as the run receipt records it): Claude Opus 5.5 through the `claude -p` command-line adapter, subscription login, no paid API |
| Marty (the question-to-lesson app) | [`morrowdock/marty`](https://github.com/morrowdock/marty) main `f2d7c5a281760b0e956334254efb52f7f1eb790c` (PR #27); prompts `marty-prompts/22` |
| Engine inside Marty | MartyGraphics `dfc521a83c8fdefc1f918a6d1bd1065e7e3a89b2` (PR #46), strict check |
| Research | On. Web search and web fetch only; at most 12 turns (12 used: 3 searches, 8 fetches); quote check on; `github.com` and GitHub content domains blocked. The research step saw only the question. Its 19-row fact table went to the plan and author steps. |
| Repairs | At most 3. Each refused try goes back to the model with the engine's reason. |
| Isolation | Each model call ran in a new empty folder with no file tools and no local settings, so the model could not read local files. No fact key, fact check or grading file was given to the model. |
| Date | 2026-11-09, run started 21:43:50 UTC; 304 s in all (298 s in model calls) |

The model's raw prompts and research replies are not published here. The run receipt holds their sizes and SHA-256
hashes.

## The tries of this run

| Try | Step | Engine result |
| --- | --- | --- |
| 1 | Author | Refused: `text.number.beat.1`. Beat 1 said "the newer **Mk4** differs"; the strict text rule counts the "4" as a number that the engine did not check. |
| 2 | Repair 1 | Marty applied 4 of the engine's own checked suggestions (`lDiff`, `lTurb`, `aR2`, `aSteer`). Then refused: `annotation.anchor.hidden.lShaft`. The shaft label in beat 7 is hidden behind the combustor. |
| 3 | Repair 2 | **Accepted** (`marty-solid check --strict` passes, no warnings). This is [lesson.json](lesson.json). |
| Follow-up | "How does the pilot steer?" | The model kept the lesson (`{"document": null}`, no change; beat 4 already poses the arms). Two answer calls: Marty's answer check flagged the first answer, because it gave the pose angles (60 and 15) that are not in the answer's evidence. The second answer is [followup-answer.txt](followup-answer.txt). Marty records the answer check as still not fixed (`answer.unsourced`); the answer is delivered either way. |

Cost equivalent of this run: about $1.16 (the sum of the per-call `total_cost_usd` that the command-line tool reports;
a subscription equivalent, not a bill).

## All 4 runs of round 2j

All four runs count. No run was stopped, dropped or repeated. We picked `r2j-opus-1` after grading because it is the
only run that met the showcase bar: 0 errors against the grader's fact key, an honest follow-up, every named engine
visible, 0 hard cuts in the video and no "not published" text. The other two accepted runs had 2 and 1 errors against
that key: both stated a load share between the arm and back engines that the key does not support, and one also gave
the wrong engine count. The grader's key is not the public fact check: the independent fact check of this lesson
(after grading) found more, see [FACT-CHECK.md](FACT-CHECK.md).

| # | Run | Model | Result | Try 1 (author) | Try 2 (repair 1) | Try 3 (repair 2) | Try 4 (repair 3) | Follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `r2j-opus-1` (this lesson) | Claude Opus 5.5 | **Accepted, try 3** | Refused `text.number.beat.1` | 4 auto-fixed, then refused `annotation.anchor.hidden.lShaft` | **Accepted** | — | No change, accepted |
| 2 | `r2j-sonnet-1` | Claude Sonnet 5.5 | Accepted, try 3 (Marty's lint fallback) | 8 auto-fixed, then refused `annotation.anchor.off.lBackT` | 1 auto-fixed; engine ok; Marty lint ("does most of the lifting") | Engine ok; Marty lint again; kept as the fallback | — | Step added |
| 3 | `r2j-opus-2` | Claude Opus 5.5 | **Refused** | Refused `component.use.unknown.name` | 4 auto-fixed, then refused `annotation.anchor.off.lExample` | Refused `annotation.arrow.hidden.aSteer` | Refused `annotation.arrow.hidden.aSteer` | Not reached |
| 4 | `r2j-sonnet-2` | Claude Sonnet 5.5 | Accepted, try 2 (by the auto-fix) | Refused `section.miss.b2.intakeLip` | 13 auto-fixed, then **accepted** | — | — | Step added |

Total: **4 runs, 3 accepted, 1 refused; 12 author and repair tries.** **1 of the 4 runs met the showcase bar.**

## Render

The lesson was rendered with `marty-solid` built from the engine at `dfc521a` (release build), one render, no
changes:

```
marty-solid render accepted-document.json <OUT> --size 1280x800 --loop-fps 30
```

The stills say "Rendered by the MartyGraphics engine from accepted-document.json (769 lines)". That is the run's file
name. Here the same bytes are in [lesson.json](lesson.json). Hashes of every file are in
[provenance.json](provenance.json).
