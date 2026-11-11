# Protocol: mechanisms-v1 (partially blind benchmark)

Status: **pre-registration. Not run.** The owner decided on 2026-11-11 to run this benchmark. Registration closes when
the pull request that adds this folder merges. At that moment the inputs in [LOCK.json](LOCK.json) are locked.

Files of this pre-registration: [QUESTIONS.json](QUESTIONS.json), [GRADER-QUESTIONS.json](GRADER-QUESTIONS.json),
[RUBRIC.md](RUBRIC.md), this file, [LOCK.json](LOCK.json), the prompt files in [prompts/](prompts/ARM2-SYSTEM.txt),
the temporal validation in [validation/](validation/README.md), the tool [tools/grader_questions.py](tools/grader_questions.py)
and [README.md](README.md). Their SHA-256 hashes are in [HASHES.txt](HASHES.txt).

## 1. Purpose and the claim under test

This is a **research-disabled product-route comparison**. It asks: for mechanism questions, does an AI model make
better explainers through Marty and the MartyGraphics engine than when it writes three.js code directly?

- **Arm 1 (MartyGraphics route):** the question goes through Marty: model → JSON → engine check → up to 3 repairs from
  the engine's exact reasons → render.
- **Arm 2 (direct three.js route):** the same model writes one HTML file with three.js, with a headless render and up
  to 3 repairs from console errors and screenshots.

The arms have **equal maximum repair counts, different route-specific assistance**: Arm 1 gets Marty's plan step and
the engine's checks; Arm 2 gets screenshots of its own render. Research is off in both arms (section 4).

Graders from other model families score the outputs with partial blinding (section 8). Every run counts. The result is
published, good or bad.

## 2. Registration, the lock and the gates

### 2.1 The lock (no tuning window)

[LOCK.json](LOCK.json) records the exact inputs at registration: the Marty commit, the engine commit, Marty's prompt
file, the three.js version and hashes, the generator model and CLI version, every prompt file of this folder, and the
seeds.

- **The benchmark always runs the locked commits.** No engine, Marty or prompt change of any kind applies to the
  benchmark after registration, also not a correctness fix. There is no pre-lock correctness window.
- **The engine is the one Marty main pins.** At registration Marty main is `1f2729518451d9cd8391bcd7f160f81385184f8f`;
  it pins MartyGraphics `38f3863d5ed27c94fccf44b5f117a43938b79455`. Arm 1 runs exactly that: Marty's check and render
  use the pinned engine, and `marty-solid` (for the story video) is built from the same commit. MartyGraphics main is
  `ca2218131e897f1138fa80c0cf23cf21cd23fa4d` at registration (7 commits after the pin); LOCK.json records it, but the benchmark does not use it,
  because a pin change would be a Marty change.
- **If a locked main moves before the merge,** LOCK.json and HASHES.txt are refreshed in this pull request and
  reviewed again before the merge. After the merge, nothing changes.
- **Before run 1,** `RUN-LOCK.json` adds what exists only after building: the harness commit, the `marty-solid`
  binary SHA-256, the Arm 2 renderer and its version, the grader tool versions, the host (hardware, macOS version) and
  the dry-run evidence. These are tools, not choices: they implement this protocol and change no input above. All input
  hashes are committed before generation.

### 2.2 Fact-check gate (done, 2026-11-11)

Two independent checkers verified every key fact with web search: GPT-6.1 Sol (`gpt-6.1-sol`) with the designer's
sources, and Gemini 4 Argon (`gemini-4-argon`) without them (blind to the earlier research). The coordinator merged the
two reports; the stricter label won. The merged result and every action are in [FACTCHECK.md](FACTCHECK.md).

- 43 of the 101 version-1 facts were corrected or re-sourced (1 WRONG: MECH-10 K2). The question texts did not change.
- Configuration-specific facts and check clauses are now conditional. Nine questions name a conventional configuration
  and accepted variants; 7 facts were added for accepted variants. A fact or clause for another configuration is N/A
  (RUBRIC.md, "Configurations and N/A").
- The mechanism checks were revised (every check the Sol report marked R, and the Gemini items). The rubric adds six
  judging limits for what pictures cannot show.
- QUESTIONS.json is now key version 2 (108 facts). Each fact records both labels, the merged label and the action.
- Open item (recorded, not blocking): the textbook citations have no page-level verification, except Norton section 9.8
  and Uicker section 8.15, which the Sol check read.

### 2.3 Temporal evidence gate (before the merge)

The graders judge motion from a frame strip (section 7). The strip must be adequate for the fastest motion that a
check needs, and equal for both graders.

1. **Objective validation (done).** [validation/temporal_evidence.py](validation/temporal_evidence.py) renders
   synthetic mechanisms at 30 fps, keeps only the strip frames, and recovers the answers from those pixels:
   rotation direction, valve timing, Geneva dwell and a short flicker. Results: [validation/RESULTS.json](validation/RESULTS.json)
   and [validation/README.md](validation/README.md).
2. **Grader validation (done, 2026-11-11; both graders pass).** Each primary grader answered the committed synthetic
   packets. Pass rule: at least 90 % of the in-scope packets correct and no wrong direction on an in-scope rotation
   packet (CANNOT JUDGE on an in-scope packet counts as not correct). Tolerances: valve angles ±45°, Geneva motion
   share ±10 points and step ±10°, flicker time ±0.2 s. The beyond-cap controls are reported, not scored.
   - **Method as run (a protocol change before registration closes).** The packet folders were renamed P01–P26,
     because the case names revealed the answers; the case-to-packet mapping is a random order with seed 20261111.
     One fresh session per grader answered all 26 packets in that order, with no answer key and no feedback. Each
     grader got only `PROMPT.txt` (with `{case}` replaced by `{packet id}`), the 26 questions without answers, and the
     sheets.
   - **Deviation.** The plan was one new session per packet (52 sessions). That was impractical. The packets are
     independent synthetic tests and no answer was shown, so one session per grader keeps the test valid; the
     deviation is recorded here.
   - **Results** ([validation/graders/SCORES.json](validation/graders/SCORES.json)): `gpt-6.1-sol` 21 of 21 in-scope
     packets correct, 0 wrong directions: **pass**. `gemini-4-argon` 20 of 21 (95.2 %), 0 wrong directions: **pass**;
     its miss was the 6-slot Geneva motion share (20–25 % against 33 %). On the controls, both graders gave a confident
     wrong direction beyond the cap (6 turn/s; the 4-arm cross at 2 turn/s) and both answered cannot judge at 5 turn/s.
     These support the motion limits and the CANNOT JUDGE answer.
   - The evidence format does not change.

### 2.4 Dry run (before run 1)

One question that is **not** in the set ("How does a bicycle's chain and sprockets change how hard you pedal?") goes
once through both arms and the whole harness. It tests the harness only, is not part of any statistic, and is
published as harness evidence.

## 3. Models

| Role | Model | ID | Access |
| --- | --- | --- | --- |
| Generator (primary, both arms) | Claude Opus 5.5 | `claude-opus-5-5` | Claude Code CLI in print mode (`claude -p`), version in LOCK.json, subscription login. No paid API. No `ANTHROPIC_*` variable passes to the child process. |
| Generator (optional, both arms) | Claude Sonnet 5.5 | `claude-sonnet-5-5` | Same as above. LOCK.json says whether it runs. |
| Grader G1 | GPT-6.1 Sol | `gpt-6.1-sol` | OpenAI Codex CLI, reasoning high, subscription login (the same tool and settings as the grader validation). No paid API. |
| Grader G2 | Gemini 4 Argon | `gemini-4-argon` | Antigravity, thinking high, Google account login (the same tool and settings as the grader validation). No paid API. |
| Graders H1..Hn (optional) | Humans, if the owner adds them before grading starts | — | Same packets and rubric. Separate analysis only. |

Model IDs do not change during the benchmark. If a model is withdrawn, the work stops, and the result is published
with what exists, as descriptive results only (section 11).

## 4. Arm 1: MartyGraphics route

In a new empty run folder:

```
marty ask "<question>" --out <run>/arm1 --model claude-opus-5-5 --repairs 3 --no-research --render
marty-solid render <run>/arm1/<accepted document> <run>/arm1/render --size 1280x800 --story-fps 30 --loop-fps 30
```

- `<question>` is the `question` string, exactly. The model sees only Marty's own prompts (the locked prompt file) and
  the question. The benchmark adds no words.
- Marty's claude-cli adapter isolates each call: a new process in a new empty folder, no tools, no MCP servers, no
  settings, no session persistence ([Marty docs/LOOP.md](https://github.com/morrowdock/marty/blob/main/docs/LOOP.md)).
- **Recording.** A pass-through shim in front of the `claude` command saves the exact bytes of every call's input and
  output (and its argv and exit code) to the run folder. It changes no byte; the dry run proves this against the
  hashes in Marty's own receipt. The shim is part of the harness, not a Marty change.
- **Repairs:** at most 3 (4 tries in all). Each refused try goes back to the model with the engine's exact reason.
- **Research is off** (`--no-research`) in both arms. Arm 2 has no equal research step, and web results change from
  run to run. So this is a research-disabled comparison of the two routes.
- **Video source:** `story.mp4`; if the render has none, `loop.mp4`.
- **Run limits:** 900 s per model call (Marty's default), 60 min per run in all.
- **Arm 1 failure:** Marty does not accept a document after the last try; or Marty exits with an error; or the render
  exits with an error or writes neither video; or the run passes 60 min.

## 5. Arm 2: direct three.js route

**Model call isolation.** The same isolation as Marty's claude-cli adapter: a new process in a new empty folder, no
tools, no MCP servers, no user, project or local settings, no session persistence, the same environment allowlist, a
900 s timeout per call. The same pass-through recording as Arm 1.

**Prompts (locked files).**

- System prompt: [prompts/ARM2-SYSTEM.txt](prompts/ARM2-SYSTEM.txt).
- Try 1 user message: the `question` string, exactly, and nothing else.
- Repair message: [prompts/ARM2-REPAIR.txt](prompts/ARM2-REPAIR.txt), with the fields filled in, followed by the five
  stills as image blocks (stream-JSON input).

**Motion limits.** The system prompt asks for the input part to turn at most one turn every 4 seconds, no part to turn
faster than one turn per second, and no motion to repeat faster than once per second. The engine's story video
uses the same input speed by default (4 s per input turn). These limits keep the motion inside the evidence's
adequate range (section 7).

**three.js.** r170 (npm `three@0.170.0`; hashes in LOCK.json), stored with the harness: `build/three.module.min.js` as
`three` and `examples/jsm/` as `three/addons/`. The harness inserts the import map at the start of `<head>`. The page
has no network access.

**Renderer.** One renderer for every Arm 2 render, chosen in RUN-LOCK.json after the dry run: R-WK (first choice), a
WKWebView harness on the same Mac as Arm 1, offscreen, 1280 × 800 CSS px, device scale 1, the system fonts; or R-CR
(only if R-WK cannot capture WebGL frames), headless Chromium with a pinned version, 1280 × 800, device scale factor 1,
on one fixed host.

**Render steps for each try.**

1. Load the page. Wait at most 30 s for `window.benchReady === true`. Read `window.benchDuration` (D); a missing or
   non-numeric value is a harness error; a value outside 10 to 60 is clamped and reported.
2. For k = 0 … 30·D − 1: call `await window.benchFrame(k / 30)`, wait for two animation frames, then capture the
   composited page (the WebGL canvas and all HTML text) as a PNG.
3. Record every uncaught exception, every `console.error` and `console.warn` line, and harness errors. Limit: 300 s
   per render.

**Tries.** Try 1 is the author call. Tries 2 to 4 are repairs (at most 3). After each try's render (not after try 4),
the model gets the repair message and answers with a new complete HTML file or with `ACCEPT`. The run's final file is
the HTML of the last try (the one the model accepted, or try 4). A reply without an `html` code block is a try with the
harness error "No ```html code block found."

**Arm 2 failure:** the final file does not render all frames (no `benchReady`, a `benchFrame` error, a capture error
or a timeout); or all five stills are nearly blank (less than 0.5 % of the pixels differ from the most common colour);
or the run passes 60 min.

## 6. Runs, order, failures and grading failures

- **Runs per question per arm:** 3 (primary generator). 20 questions × 2 arms × 3 runs = **120 generation runs**. The
  optional second generator: 2 runs per question per arm (80 more), analysed apart.
- **Pairs:** run r of Arm 1 and run r of Arm 2 for the same question form pair `<question id>-r<r>` (60 pairs).
- **Order:** all run slots `(question id, arm, r)` in sorted order, shuffled once with Python
  `random.Random(20261111).shuffle`, run one at a time on one host.
- **Every run counts.** A failed run (sections 4 and 5) scores zero (section 11). Model errors, refusals, timeouts
  after the model started, invalid JSON or HTML and render failures are failures.
- **Void runs (infrastructure only).** A run is VOID only if the CLI records a host or network fault or a subscription
  usage-limit error. It is logged with its error text and run again in the same slot (`-v2`, `-v3`). A third fault in
  the same slot counts as a failure. Every void is published with its log.
- **No reruns for quality.** Nobody looks at outputs or scores until all runs are generated. No run is repeated,
  dropped or replaced for any other reason.
- **Grading failures.** A grader reply that is not valid JSON in the rubric's form gets one message with the parse
  error in the same session. If it is still invalid, a new session tries again, up to 2 new sessions (3 sessions in
  all). After that, that grader's grade is **missing**. If both graders' grades are missing for an output, the output
  is **ungraded**: it is never dropped silently and never scored 0. It is left out of the score means, listed by id,
  and counted per arm in the result. A preference with both grades missing is **unjudged**, listed and counted the same
  way.

## 7. Artifact set and grader evidence (the same for both arms)

**Content length.** Arm 1: the length of `story.mp4` (or `loop.mp4`). Arm 2: `benchDuration`. Content longer than
60 s is cut at 60 s (the result counts how often); content shorter than 10 s holds its last frame to 10 s. Call the
result L.

**Same length in a pair.** Both outputs of a pair are held on their last frame to T = the larger L of the two. An
output whose pair partner failed keeps T = L.

**Normalisation (both arms).**

1. **One lossy generation for both.** Arm 1's source is the engine's H.264 video. Arm 2's PNG captures are first
   encoded to an intermediate H.264 file with the same AVFoundation writer settings as the engine's story writer at the
   locked engine. So both arms pass through exactly one lossy encode before normalisation.
2. Decode the source at 30 fps, fix the length to T as above, and check the size (1280 × 800; any other size is a
   harness error to fix before grading, not a run failure).
3. Mask branding and provenance (section 8).
4. Write the artifact set from the masked frames:

| File | Content |
| --- | --- |
| `video.mp4` | 1280 × 800, 30 fps, 30·T frames, H.264, no audio, no metadata beyond what the format requires, moov atom first. Published; given to human graders; **not** given to the primary graders (equal evidence). |
| `still-1.png` … `still-5.png` | Frames at 10, 30, 50, 70 and 90 % of L, 1280 × 800, RGB, no text chunks or other metadata. |
| `sheets/sheet-NN.png` | The **frame strip**: every 3rd frame (10 fps) over all of T, as 256 × 160 thumbnails (1/5 size) in sheets of 5 × 5, each with its time under it ("t=12.30 s"), in reading order. |
| `TEXT.txt` | OCR transcript: Apple Vision text recognition (accurate level, en-US, language correction off) on frames every 0.5 s; lines in time order; repeated consecutive lines removed. |

**Equal evidence.** Both primary graders get exactly the same files: the five stills, the sheets and `TEXT.txt`. No
grader gets the video, so no grader has more temporal evidence than the other.

**Adequacy rule.** The strip is adequate for a motion when a visible feature moves at most 1/4 of its repeat period
between strip frames (sampling at 4 × the feature's event frequency or more). At 10 fps this covers:

- a part with one non-repeating feature (a pin, crank, marker) up to 2.5 turns per second;
- a feature that repeats k times around a part up to 2.5 / k turns per second;
- the Arm 2 limits (input ≤ 0.25 turn/s, any part ≤ 1 turn/s) and the engine's default story speed (input 0.25
  turn/s), including the peak speed of a 4-slot Geneva wheel at that input speed (21.7° per strip frame against a
  22.5° limit);
- a disappearance of 0.1 s (3 video frames) or longer: at least one strip frame always falls inside it.

Faster motion, or a flicker shorter than 0.1 s, is outside the evidence. The rubric's D5 grades only flickers of
0.1 s or longer. The temporal validation (section 2.3) shows that inside the rule the answers are recovered correctly,
and that beyond it the evidence can give a confident wrong direction (aliasing). That is why a grader answers CANNOT
JUDGE, not FAIL, when it cannot see a direction or timing (RUBRIC.md).

## 8. Partial blinding

Full blinding is not possible, so this design is **partial blinding**. The render styles differ (SceneKit shading in
Arm 1, WebGL in Arm 2), and the layouts of titles and captions differ.

**Masking: branding and provenance only.** The harness runs OCR on every frame and covers only the matched text span
(Vision's box for the matched character range, plus 3 px), filled with the median colour of the 1 px ring around the
box. Rules (case-insensitive):

- **P1 provenance clause:** from `Rendered by` to the end of its line (the engine footer "Rendered by the MartyGraphics
  solid engine from <file> (<n> lines)").
- **B1 branding words:** the whole words `MartyGraphics`, `Marty`, `three.js`, `threejs`, `WebGL`, `Claude`.
- **F1 file names:** a token that ends in `.json` or `.html`.

**Honest limitation labels are kept**, in both arms: the engine's legend and tier words ("Solved 4 (animation
ratios)", "Schematic motion", "Schematic", "Not checked", "Some motion is schematic", "Arrow lengths are not to scale")
and any similar label that Arm 2 writes. The rubric says such labels are never errors. They can reveal Arm 1; that is
an accepted part of the residual risk.

After masking, the harness runs OCR again on the stills; a remaining match gets a cover with 6 px padding. Matches that
still remain are logged; nobody edits a frame by hand.

**Labels and tokens.** After all runs are generated and normalised:

1. The operator makes a seed: 32 bytes from the operating system's random source, as hex. The operator commits
   `results/BLINDING-COMMITMENT.txt` (the SHA-256 of the seed's hex string) to the public branch **before** any grader
   call. The seed stays private until grading ends.
2. **Score packets** are anonymous and hold one output: folder `output/`, the question's entry from
   GRADER-QUESTIONS.json as `question.json`, and RUBRIC.md. The output token is the first 12 hex characters of
   HMAC-SHA256(seed, "<question id>-r<r>-arm<a>:token"). **Every rendered output gets a score call**, also an output
   whose pair partner failed.
3. **Preference packets** exist only for pairs where both outputs rendered: folders `A/` and `B/`. Arm 1 is **A** if
   the first byte of HMAC-SHA256(seed, "<pair id>:side") is even. The pair token is the first 12 hex characters of
   HMAC-SHA256(seed, "<pair id>:pair").
4. Each grader's order of calls is a permutation from HMAC-SHA256(seed, "order:" + grader id). Score calls and
   preference calls are separate sessions.
5. After grading ends, the operator commits `results/BLINDING-SEED.txt` and the arm mapping. Anyone can check the
   commitment and recompute every token and label.

**File hygiene.** The harness rewrites every artifact, so encoder tags, creation times, file names and PNG chunks
carry no arm signal. Packets hold nothing else.

**Automatic preference.** A pair with one failed run gets no preference call: the rendered output wins. A pair with two
failed runs is a tie. These are computed, not graded, and are reported apart from graded preferences.

**Measure of the residual risk.** After a pair's preference is stored, a separate call
([prompts/GRADER-GUESS.txt](prompts/GRADER-GUESS.txt)) asks the grader whether A and B came from different tools and
which one used a dedicated 3D engine. It never changes a grade. The result publishes, per grader, the counts of correct,
wrong and cannot-tell guesses and an exact binomial test of correct against wrong (null: 50 %).

## 9. Graders

- **Independence.** G1 and G2 make every call. Each call is a new session in a new empty folder that holds only the
  packet. No web, no memory, no custom instructions, no tools except reading the packet files. Neither grader sees the
  other's grades.
- **Prompts (locked files):** [prompts/GRADER-SCORE.txt](prompts/GRADER-SCORE.txt),
  [prompts/GRADER-PREFERENCE.txt](prompts/GRADER-PREFERENCE.txt), [prompts/GRADER-GUESS.txt](prompts/GRADER-GUESS.txt).
- **Question view.** Graders get only [GRADER-QUESTIONS.json](GRADER-QUESTIONS.json): the question text, the key facts
  with their accepted variants, and the mechanism checks. [tools/grader_questions.py](tools/grader_questions.py) makes
  it from QUESTIONS.json and refuses words that tell how an output was made. No category, sources, check labels,
  designer notes or `nearShipped` notes reach a grader.
- **Humans (optional).** If the owner adds human graders before grading starts, they get the same packets plus
  `video.mp4`, the same rubric and their own orders. Their grades are reported apart and do not enter the primary
  merge.
- **Grading starts** only after all generation runs are finished, normalised, masked and packed, and the commitment is
  pushed.

## 10. Merging grades and agreement

**Adequate judgments.** For `M3` and `M4`, a CANNOT JUDGE answer is not a judgment. An N/A answer (the check does not
apply to the shown accepted variant) is not a judgment either. "Stricter wins" applies only between two judgments that
were both made (PASS, FAIL or NOT SHOWN):

| Item | Merge (G1 and G2; a missing grade leaves the other) |
| --- | --- |
| each check `M1`–`M5` | Both judged: PASS only if both PASS. One judged, one CANNOT JUDGE or N/A: the judgment. Neither judged: the check is **unjudged** (both N/A: **N/A**). |
| (a) mechanism score | 5 × (merged PASS) / (judged checks). Unjudged and N/A checks leave the numerator and the denominator. If no check is judged, the score is undefined and the output counts as ungraded for the primary metric. |
| (b) errors | The larger count. Coverage: the smaller fraction (covered applicable core facts / applicable core facts). |
| (c) clarity | The lower score. |
| (d) defects | The larger count, for major and for minor apart. |
| (e) preference | Same answer: that answer. One "tie" and one side: tie. A against B: tie. |

The result reports the CANNOT JUDGE, unjudged and N/A counts per arm and per check, and the configurations that each
grader identified (with their agreement).

**Agreement statistics** (G1 against G2, on the outputs and pairs that both graded), each with a 95 % bootstrap
interval over items, labelled exploratory:

- checks: percent agreement and Cohen's kappa (PASS against not PASS, on checks both judged), pooled and per kind;
  the share of checks where one grader judged and the other did not;
- mechanism score, errors, coverage and defect counts: Krippendorff's alpha (interval) and Spearman's rho;
- clarity: Cohen's kappa with quadratic weights;
- preference: Cohen's kappa over {A, B, tie}.

## 11. Analysis plan

Fixed in advance. The analysis script lands with the harness and is tested on synthetic data before run 1.

**Scores of a failed run.** Mechanism score 0, clarity 0, coverage 0 (as a fraction). Errors = E_fail(q) = 1 + the largest merged
error count of any graded output of question q in either arm (a failure is always worse than any graded output).
Defects are not defined for a failed run. Ungraded outputs are left out (section 6).

**Primary metric.** The merged mechanism score (0 to 5) per run. For question q and arm a, M(q, a) = the mean over its
failed and graded runs. If a (q, a) has no failed or graded run, M(q, a) is **undefined**, and question q leaves the
primary test (the count is reported). The paired difference is d(q) = M(q, Arm 1) − M(q, Arm 2).

**Primary test and the verdict.** The verdict is a **question-level sign-test result**: an exact two-sided sign test
over the questions with a defined d(q) ≠ 0 (binomial, p = 0.5), α = 0.05. If every defined d(q) is 0 (all ties),
p = 1. Effect size: the mean of the defined d(q), with a 95 % percentile bootstrap interval (resample the questions
with replacement, 10 000 resamples, NumPy `default_rng(20261111)`).

**Opposite-signed effect.** If the mean of d(q) has the opposite sign of the sign-test majority (more questions favour
one arm, the mean favours the other), the report says so in its first paragraph, with both numbers.

**Exploratory analyses.** Everything below is **exploratory and unadjusted** (no correction for multiple tests). An
exploratory result can never be an alternative route to a win, a loss or any claim of superiority. Each gives an
estimate and a 95 % interval by the same question-level bootstrap.

1. Text errors per run (merged): mean per arm and the paired difference per question; also only pairs where both
   rendered.
2. Graded pairwise preference: Arm 1 win rate = wins / (wins + losses), ties apart; and the same with automatic
   preferences included; the question-level winner by pair wins.
3. Teaching clarity, as the primary method.
4. Visual defects: mean major and minor counts per graded output, per arm.
5. Success rate: rendered runs / all runs, per arm and per question.
6. Coverage: covered applicable core key facts / applicable core key facts.
7. CANNOT JUDGE, unjudged and N/A counts per arm and per check; the configurations shown per arm.
8. Cost of the route: tries used, wall time, and the CLI's `total_cost_usd` sum (a subscription equivalent, not a
   bill), per arm.
9. Per category table.
10. Grader agreement (section 10) and the primary analysis for each grader alone.
11. Blinding check (section 8).
12. Optional second generator and human graders: the same plan, reported apart, never a verdict.

**Prespecified sensitivity analysis (descriptive).** The primary analysis repeated without the 5 questions that
QUESTIONS.json marks `nearShipped` (MECH-01, MECH-03, MECH-08, MECH-17, MECH-18): the defined d(q), the counts of
positive and negative d(q), the mean with its interval, and the sign-test p as a description. It does not change the
verdict.

**Zero denominators.** Any summary with a zero denominator (for example a win rate with no wins and no losses) is
reported as **undefined**, with its counts.

**Power.** With 20 questions and no ties, the sign test needs at least 15 of 20 questions to favour one arm (two-sided
p = 0.041). A small true difference will probably give "no conclusion". This is accepted and will be said.

**Stopping rule and incomplete data.** The design is fixed: all 120 runs (and the optional 80) are generated before any
grading. There is no interim look at outputs or scores, no early stop for success or futility, and no extra run. Usage
limits or host faults only pause the work. The registered verdict needs the **completed design**: every run slot
generated (or failed), and every grading call made under section 6. If the design is not complete 21 days after run 1,
or if more than 5 % of the rendered outputs are ungraded, the result is published with **descriptive results only**
and no verdict.

## 12. Verdict and publication

| Verdict | Condition (primary test, completed design only) |
| --- | --- |
| **Win** for the MartyGraphics route | p < 0.05 and more questions have d(q) > 0 than d(q) < 0. |
| **Loss** for the MartyGraphics route | p < 0.05 and more questions have d(q) < 0 than d(q) > 0. |
| **No conclusion** | Any other outcome. The report gives the direction and the interval, and does not call it a win or a loss. |

The report gives the primary verdict first, then the opposite-signed effect statement if it applies, then the
sensitivity analysis and every exploratory result, including those that go against the verdict.

**Publication, whatever the result.** Within 7 days after grading ends, a pull request to this public repository adds
`benchmark/mechanisms-v1/results/` with all generation and grading evidence and a `SHA256SUMS` file for every item:

- every candidate JSON (Arm 1, every try) and HTML file (Arm 2, every try);
- every model message: the exact input and output bytes of every call in both arms, with argv and exit codes;
- all repair feedback: the engine's reasons, Marty's attached facts, the Arm 2 render reports and screenshots;
- all logs and receipts, `RUNS.csv` (every run, failure and void) and the void logs;
- the **original unmasked renders** (engine stills and videos, Arm 2 captures and intermediate videos) and the
  masked artifact sets and packets;
- the raw grader replies, the merged table, the analysis code and output, LOCK.json, RUN-LOCK.json, the seed, the
  commitment and the **arm mapping**.

Only credentials are redacted (login tokens, API keys, cookies), each replaced by `[REDACTED]`, with a list of where.
A secret scan (Gitleaks) runs over the evidence before publication. Files too large for the repository go in a GitHub
release asset with the same hashes. The main README links the result. A showcase or social post that uses a benchmark
output links the full result and states the verdict as defined here.

## 13. Amendments

Changes after registration go in `AMENDMENTS.md` (dated, with the reason, and the old and new hashes).

- **After registration and before run 1:** only RUN-LOCK.json, the harness, and typing fixes that do not change
  meaning. No change to questions, key facts, checks, prompts, the rubric, the scoring, the evidence format or the
  analysis.
- **After run 1:** only clarifications that cannot change any score, marked "no score effect".
- **After grading starts:** no change.
- A change that is needed but not allowed starts a new version (`mechanisms-v2`) with a new pre-registration. The v1
  result is still published.

## 14. Residual risks and known limits

1. **Partial blinding.** The look of the renders and the kept limitation labels can reveal the arm (section 8);
   measured, not removed.
2. **Shipped and worked examples.** Five questions are near shipped examples (`nearShipped` in QUESTIONS.json).
   Marty's prompts or the component library may contain related worked examples. The sensitivity analysis leaves them
   out.
3. **Different route-specific assistance.** Arm 1 gets Marty's plan step and the engine's checks; Arm 2 gets
   screenshots of its own render; the repair maximum is equal. This compares the routes as products.
4. **Older engine.** Arm 1 uses the engine that Marty main pins (`38f3863`), 7 commits behind MartyGraphics main at
   registration. The result is about that locked route.
5. **Motion limits are asked, not enforced.** Arm 2 is asked to stay inside the limits; Arm 1 uses the engine's default
   story speed. The grader validation showed that both graders can give a confident wrong direction for motion beyond
   the limits, instead of CANNOT JUDGE. So motion faster than the limits can cost either arm a wrong M3 or M4 result.
   The result reports CANNOT JUDGE counts per arm.
6. **Same-family key.** A Claude model wrote the key facts and generates both arms. The fact-check gate uses two other
   model families.
7. **Small set.** 20 questions chosen by one designer. Low power for small effects (section 11).
8. **Non-determinism.** Model outputs vary between runs; 3 runs per question per arm reduce this.
9. **Graders are models.** Their errors are measured by agreement statistics and the grader validation; humans are
   optional.
10. **OCR.** `TEXT.txt` and the masks depend on OCR; the rubric makes the images win, and remaining mask misses are
    logged.

## 15. Roles

- **Owner** (Collin Craig): approves the registration, may add human graders, reviews and merges pull requests.
- **Operator:** an agent session that runs the harness. It sees which arm made each run, so it never grades and never
  opens graded outputs before the seed is published.
- **Graders:** G1 and G2 (and humans, if added), blind as above.
- **Designer:** this pre-registration (Claude Opus 5.5, 2026-11-11). The designer did not run any part of the benchmark.
