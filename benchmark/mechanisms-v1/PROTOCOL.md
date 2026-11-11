# Protocol: mechanisms-v1 (blind benchmark)

Status: **pre-registered on 2026-11-11. Not run.** The owner decided on 2026-11-11 to run this blind benchmark. An
engine feature freeze is active until the result is published.

Files of this pre-registration: [QUESTIONS.json](QUESTIONS.json), [RUBRIC.md](RUBRIC.md), this file and
[README.md](README.md). Their SHA-256 hashes are in [HASHES.txt](HASHES.txt).

## 1. Purpose and the claim under test

MartyGraphics claims that an AI model makes better mechanism explainers through the engine (the model writes JSON, the
engine checks it and refuses wrong scenes with exact reasons, the model repairs, the engine renders) than when it writes
3D code directly.

This benchmark tests that claim on 20 fixed mechanism questions, with the same model in both arms:

- **Arm 1 (MartyGraphics):** the question goes through Marty: model → JSON → engine check → up to 3 repairs from the
  engine's exact reasons → render.
- **Arm 2 (direct three.js):** the same model writes one HTML file with three.js. It gets equal help: a three.js system
  prompt, a headless render, and up to 3 repairs from console errors and screenshots.

Blind graders from other model families score the rendered outputs. Every run counts. The result is published, good or
bad.

## 2. Fixed inputs, the lock and the fact-check gate

1. **Questions and key facts:** [QUESTIONS.json](QUESTIONS.json). The `question` string goes to both arms byte for
   byte, with no other words.
2. **Rubric:** [RUBRIC.md](RUBRIC.md).
3. **Fact-check gate (before run 1).** An earlier lesson showed that one research pass can contain real errors
   ([jet-suit fact check](../../docs/assets/jet-suit-ai/FACT-CHECK.md)). So, before run 1, two independent checkers
   verify every key fact with web search:
   - Checker 1: GPT-6.1 Sol. It gets the questions, the key facts and the designer's sources.
   - Checker 2: Gemini 4 Argon. It gets the questions and the key facts **without** the designer's sources (blind to the
     earlier research).
   - Each checker labels each key fact VERIFIED, CLAIM, PLAUSIBLE, UNKNOWN or WRONG, with at least one source (URL,
     publisher, date) per label, and checks each textbook citation.
   - Merge: the stricter label wins. A fact that either checker labels WRONG or UNKNOWN is corrected from a cited source
     or removed. A correction changes only `keyFacts` and, where a check quotes the corrected fact, the matching words of
     `mechanismChecks`. The question text does not change.
   - Output: `FACT-CHECK.md` (both reports and the merged key) and amendment 1 ([section 13](#13-amendments)) with new
     hashes. No benchmark output exists at this time, so the checkers cannot be influenced by results.
4. **The lock (before run 1).** `LOCK.json` records, before run 1 and after one dry run (below):
   - Marty commit, engine commit (the engine that Marty pins), the `marty-solid` binary SHA-256 (release build from that
     engine commit), Marty's prompt version (`marty-prompts/<n>`);
   - the Claude Code CLI version, the exact argv of every model call kind, and the model IDs;
   - the SHA-256 of the Arm 2 system prompt file, of the three.js files and of the harness commit;
   - the Arm 2 renderer (one choice for all runs, [section 5](#5-arm-2-the-same-model-writes-threejs)) and its version;
   - the grader CLI versions and exact grader model strings;
   - the OCR settings, the host (hardware model, macOS version), and the run-order seed `20261111`;
   - whether the optional second generator model runs ([section 3](#3-models)).
5. **Dry run.** One question that is **not** in the set ("How does a bicycle's chain and sprockets change how hard you
   pedal?") goes once through both arms and the whole harness (normalise, mask, blind, one grader call per grader). It
   tests the harness only. It is not graded for the result and is not part of any statistic. It is published as harness
   evidence.
6. **Harness code.** The tools that run the arms, normalise artifacts, mask, blind, call graders and analyse land in a
   separate reviewed pull request under `benchmark/mechanisms-v1/harness/` before the lock. The analysis script is
   tested on synthetic data before run 1. The harness is not engine code.

## 3. Models

| Role | Model | ID | Access |
| --- | --- | --- | --- |
| Generator (primary, both arms) | Claude Opus 5.5 | `claude-opus-5-5` | Claude Code CLI in print mode (`claude -p`), subscription login. No paid API. No `ANTHROPIC_*` variable passes to the child process. |
| Generator (optional, both arms) | Claude Sonnet 5.5 | `claude-sonnet-5-5` | Same as above. The lock says yes or no before run 1. |
| Grader G1 | GPT-6.1 Sol | exact model string recorded in `LOCK.json` | OpenAI Codex CLI, subscription login. No paid API. |
| Grader G2 | Gemini 4 Argon | exact model string recorded in `LOCK.json` | Gemini CLI, Google account login. No paid API. |
| Graders H1..Hn (optional) | Humans, if the owner adds them before grading starts | — | Same packets and rubric. Secondary analysis only. |

The model IDs do not change during the benchmark. If a grader model is withdrawn during grading, grading stops; the
result is published with the grades that exist, labelled incomplete.

## 4. Arm 1: MartyGraphics through Marty

**Software.** [Marty](https://github.com/morrowdock/marty) (public). At pre-registration, Marty main is
`0593bcda098365df514756b21e3b907f011d6b88` and pins MartyGraphics `38f3863d5ed27c94fccf44b5f117a43938b79455`.
MartyGraphics main is `933db57c6beb9863f543c4519d35ece84952ebb3` (5 commits after that pin; the last one, #54, is a
correctness fix to #53, not a feature).

- **The benchmark engine** is MartyGraphics main at the lock. The feature freeze allows no new engine feature before
  the result. A correctness fix may still merge before the lock; it then becomes the benchmark engine. After the lock,
  the benchmark uses only the locked engine, whatever merges later.
- Before run 1, a separate reviewed Marty pull request moves only Marty's pin to that engine commit (no prompt change).
  If Marty's tests fail with that pin, the benchmark uses Marty `0593bcd` with its own pin, and `LOCK.json` says why.
- `marty-solid` is built (release) from the same engine commit that Marty pins.

**Exact steps per run.** In a new empty run folder:

```
marty ask "<question>" --out <run>/arm1 --model claude-opus-5-5 --repairs 3 --no-research --render
marty-solid render <run>/arm1/<accepted document> <run>/arm1/render --size 1280x800 --story-fps 30 --loop-fps 30
```

- `<question>` is the `question` string, exactly. The model sees only Marty's own prompts (the version in `LOCK.json`)
  and the question. The benchmark adds no words.
- Marty's claude-cli adapter isolates each call: a new process in a new empty folder, no tools, no MCP servers, no
  settings, no session persistence ([Marty docs/LOOP.md](https://github.com/morrowdock/marty/blob/main/docs/LOOP.md)).
- **Repairs:** at most 3 (4 tries in all). Each refused try goes back to the model with the engine's exact reason.
- **Research is off** (`--no-research`) in both arms. Reason: Arm 2 has no equal research step in the owner's design,
  and web results change from run to run. This benchmark compares the render route at equal knowledge.
- **Video source:** `story.mp4`. If the render has no `story.mp4`, the harness uses `loop.mp4` (repeated to fill 20 s,
  because it is a seamless loop).
- **Run limits:** 900 s per model call (Marty's default), 60 min per run in all.
- **Arm 1 failure:** Marty does not accept a document after the last try; or Marty exits with an error; or the render
  exits with an error or writes neither `story.mp4` nor `loop.mp4`; or the run passes 60 min.

## 5. Arm 2: the same model writes three.js

**Model call isolation.** The same isolation as Marty's claude-cli adapter: a new process in a new empty folder, no
tools, no MCP servers, no user, project or local settings, no session persistence, the same environment allowlist, a
900 s timeout per call. The system prompt is passed as a file. The exact argv is in `LOCK.json`.

**three.js.** Version r170 (npm `three@0.170.0`), stored locally with the harness: `build/three.module.min.js` as
`three` and `examples/jsm/` as `three/addons/`. The harness inserts the import map at the start of `<head>`. The page
has no network access.

**Renderer.** One renderer for every Arm 2 render, chosen in the lock after the dry run:

- **R-WK (first choice):** a WKWebView harness on the same Mac as Arm 1, offscreen window, 1280 × 800 CSS px, device
  scale 1, the same system fonts as the engine.
- **R-CR (fallback, only if R-WK cannot capture WebGL frames in the dry run):** headless Chromium (version pinned in the
  lock), 1280 × 800, device scale factor 1, GPU on, on one fixed host.

**Render steps for each try.**

1. Load the page. Wait at most 30 s for `window.benchReady === true`.
2. For k = 0 … 599: call `await window.benchFrame(k / 30)`, wait for two animation frames, then capture the composited
   page (the WebGL canvas and all HTML text) as a PNG.
3. Record every uncaught exception, every `console.error` and `console.warn` line, and harness errors (no `benchReady`,
   no `benchFrame`, a `benchFrame` that throws, a capture error). Limit: 300 s per render.

**Tries.** Try 1 is the author call. Tries 2 to 4 are repairs (at most 3). After each try's render (not after try 4),
the model gets the render report and the five stills, and answers with a new complete HTML file or with `ACCEPT`.

- The run's final file is the HTML of the last try (the try the model accepted, or try 4).
- A reply without an `html` code block is a try with the harness error "No ```html code block found."
- **Arm 2 failure:** the final file does not render all 600 frames (no `benchReady`, a `benchFrame` error, a capture
  error, or a timeout); or all five stills are nearly blank (less than 0.5 % of the pixels differ from the most common
  colour); or the run passes 60 min.

### Arm 2 system prompt (exact)

The text between the fences, encoded as UTF-8 with one final newline, is the file `ARM2-SYSTEM.txt`. Its SHA-256 goes
in the lock.

```text
You explain how things work with 3D animation. A learner asked the question in the user message. Write ONE self-contained HTML file that uses three.js to show a 20-second animated 3D explainer that answers the question.

Requirements:
1. Model the mechanism in 3D. Show its main parts, connected the way they really are. Animate them correctly: directions of motion, speed ratios and timing. Make the geometry physically possible: no part passes through another part, and links keep their length.
2. Teach in short steps. Put the explanation on screen as text: a title, short captions that change with the steps, and labels on the parts. Write for a learner with no background. Every statement must be true. Do not invent numbers. If you show example values, say that they are examples.
3. The page is 1280 x 800 CSS pixels at device pixel ratio 1. Keep every part and every text inside the frame and readable (text at least 14 px high).
4. Import three.js only as `import * as THREE from 'three'` and add-ons from 'three/addons/...'. The harness inserts an import map for three.js r170. Do not write an import map. Use no other network resource, file, font or image.
5. Define `window.benchFrame = async (t) => { ... }`. It must draw the complete frame (the 3D view and all text) for time t in seconds, 0 <= t < 20, and it must give the same picture every time for the same t. Do not use the clock, requestAnimationFrame timing or unseeded random numbers. The harness calls benchFrame for t = 0, 1/30, 2/30, ... and captures each frame. Set `window.benchReady = true` when setup is complete.
6. Answer with the complete HTML file in one ```html code block and nothing else.
```

### Arm 2 user message for try 1 (exact)

The `question` string, exactly, and nothing else.

### Arm 2 repair message (exact template)

The repair call is a new process with the same system prompt. Its user message has this text, then the five stills
(t = 2, 6, 10, 14, 18 s; 1280 × 800 PNG) as image blocks (stream-JSON input; the exact argv is in the lock).

~~~~text
Question: <question>

Your HTML file (try <n> of 4):
```html
<the HTML of try n>
```

Render report:
- Harness errors: <list, or "none">
- Uncaught exceptions: <list, or "none">
- Console errors and warnings (first 50 lines): <list, or "none">

The attached images are your page's frames at t = 2, 6, 10, 14 and 18 s, at 1280 x 800.

Check the mechanism, the text and the frames. If you want to change the file, answer with the complete new HTML file in one ```html code block. If the file is final, answer with exactly ACCEPT. You have <4 - n> repair(s) left.
~~~~

## 6. Runs, order and failures

- **Runs per question per arm:** 3 (primary generator). 20 questions × 2 arms × 3 runs = **120 generation runs**. If the
  optional second generator runs: 2 runs per question per arm (80 more runs), analysed separately.
- **Pairs:** run r of Arm 1 and run r of Arm 2 for the same question form pair `<question id>-r<r>` (60 pairs).
- **Order:** all run slots `(question id, arm, r)` in sorted order, shuffled once with Python
  `random.Random(20261111).shuffle`. Runs go one at a time in that order, on one host.
- **Every run counts.** A failed run (sections 4 and 5) counts and scores zero ([section 11](#11-analysis-plan)).
  Model errors, refusals, timeouts after the model started, invalid JSON or HTML and render failures are failures.
- **Void runs (infrastructure only).** A run is VOID only if the CLI records a host or network fault or a subscription
  usage-limit error. The operator logs the void with its error text and runs the same slot again (suffix `-v2`, `-v3`).
  A third fault in the same slot counts as a failure. Every void is published with its log.
- **No reruns for quality.** Nobody looks at outputs or scores until all runs are generated. No run is repeated,
  dropped or replaced for any other reason.

## 7. Artifact set: the same output form for both arms

Each successful run becomes the same artifact set:

| File | Content |
| --- | --- |
| `video.mp4` | 1280 × 800, 30 fps, exactly 600 frames (20.000 s), H.264, no audio, no metadata beyond what the format requires, moov atom first. |
| `still-1.png` … `still-5.png` | Frames k = 60, 180, 300, 420, 540 (t = 2, 6, 10, 14, 18 s), 1280 × 800, RGB, no text chunks or other metadata. |
| `frames/f01.png` … `f20.png` | Frames at t = 0.5, 1.5, … 19.5 s (for graders that cannot read video). |
| `TEXT.txt` | OCR transcript: Apple Vision text recognition (accurate level, en-US, language correction off) on 40 frames at t = 0.25 + 0.5 j s; lines in time order; repeated consecutive lines removed. |

**Normalisation steps (both arms).**

1. **One lossy generation for both.** Arm 1's source is the engine's H.264 `story.mp4`. Arm 2's 600 PNG captures are
   first encoded to an intermediate H.264 file with the same AVFoundation writer settings as the engine's story writer
   at the pinned engine (recorded in the lock). So both arms pass through exactly one lossy encode before
   normalisation.
2. **Decode** the source at 30 fps. Source length L.
3. **Fix the length to 20 s.** Output frame k shows the source at t = k / 30 if t < L. After the end: `story.mp4` and
   Arm 2 hold the last frame; `loop.mp4` repeats from its start. Content after 20 s is cut. Neither arm is told this
   rule; Arm 2's contract asks for 20 s.
4. **Size.** The source must be 1280 × 800. Any other size is a harness error to fix before grading (not a run failure).
5. **Mask** the frames ([section 8](#8-blinding)).
6. **Write** the stills and grader frames as PNG from the masked decoded frames, then encode `video.mp4` from all 600
   masked frames with fixed settings, then move the moov atom to the front (AVFoundation pass-through remux).
7. **OCR** the masked frames for `TEXT.txt`.

## 8. Blinding

**Masking (both arms, same rules).** The harness runs OCR on every frame and covers each OCR line that matches a rule
below. The cover is the line's box plus 4 px, filled with the median colour of the 1 px ring around the box. After
masking, the harness runs OCR again on the stills; a remaining match gets a cover with 8 px padding. Matches that still
remain are logged; nobody edits a frame by hand.

- **R1 (substring, case-insensitive):** `martygraphics`, `marty`, `rendered by`, `three.js`, `threejs`, `webgl`,
  `accepted-document`, `claude`, `opus`, `.json`, `.html`.
- **R2 (whole line, the engine's legend and tier-chip words at the pin):**
  `^\s*(Solved|Numbers solved|Checked|Schematic motion|Schematic|Not checked)(\s+\d+(\s*\([^)]*\))?)?(\s*·\s*(Solved|Numbers solved|Checked|Schematic motion|Schematic|Not checked)(\s+\d+(\s*\([^)]*\))?)?)*\s*$`
- **R3 (substring, case-insensitive):** `some motion is schematic`, `arrow lengths are not to scale`.

R1 covers the engine footer ("Rendered by the MartyGraphics solid engine from …"). R2 and R3 cover the engine's legend
line and honesty notes. These are honest labels, not mechanism claims, so masking them costs Arm 1 no points in the
rubric; it does remove a possible arm signal.

**Labels.** After all runs are generated and normalised:

1. The operator makes a seed: 32 bytes from the operating system's random source, as hex.
2. The operator commits `results/BLINDING-COMMITMENT.txt` with the SHA-256 of the seed's hex string to the public
   branch **before** any grader call. The seed itself stays private until grading ends.
3. For pair id p: Arm 1 is **A** if the first byte of HMAC-SHA256(seed, p + ":side") is even; else Arm 1 is **B**. The
   pair token is the first 12 hex characters of HMAC-SHA256(seed, p + ":token"). Graders see the question id and the
   pair token, never the run index or the arm.
4. Each grader's pair order is a permutation from HMAC-SHA256(seed, "order:" + grader id).
5. After grading ends, the operator commits `results/BLINDING-SEED.txt`. Anyone can check the commitment and recompute
   every label.

**File hygiene.** Every artifact is rewritten by the harness (step 6 above), so encoder tags, creation times, file names
and PNG chunks carry no arm signal. Packet folders contain only `A/` and `B/` artifact sets, the question's entry from
QUESTIONS.json and RUBRIC.md.

**Failed runs.** A pair with one failed run is not shown to graders: the rendered run wins the preference and the failed
run scores zero ([section 11](#11-analysis-plan)). A pair with two failed runs is a tie. So graders see only pairs with
two rendered outputs, and a failure cannot reveal an arm.

**Residual risk (stated honestly).** Full blinding is not possible:

- The look differs: SceneKit physically based shading in Arm 1, WebGL in Arm 2; title and caption layouts differ; text
  rendering may differ (R-WK uses the same system fonts; R-CR does not).
- Masked patches will mostly appear in Arm 1, because the engine writes a footer and a legend.
- A grader may know the MartyGraphics look from public images.

**Measure of the risk.** After each pair's grade is stored, a separate call asks the grader whether A and B came from
different tools and which one used a dedicated 3D engine (A, B or cannot tell). This never changes a score. The result
reports, per grader, the counts of correct, wrong and cannot-tell guesses, and an exact binomial test of correct against
wrong (null: 50 %).

## 9. Graders

- **Independence.** G1 and G2 grade every shown pair. Each pair is a new session in a new empty folder that holds only
  the packet. No web, no memory, no custom instructions, no tools except reading the packet files. Neither grader sees
  the other's grades.
- **Inputs.** G2 (Gemini) gets `video.mp4`, the five stills and `TEXT.txt` for each output. G1 (GPT) gets the 20 grader
  frames in place of the video, plus the five stills and `TEXT.txt`. Each grader gets the same form for both arms.
- **Prompt (exact):**

```text
You are a blind grader for a benchmark of 3D mechanism explainers. Read RUBRIC.md and question.json in this folder. Folders A/ and B/ each hold one output for this question: stills, a video (or frames from it) and TEXT.txt. Grade A and B exactly as RUBRIC.md says, then give the preference. Do not guess how the outputs were made. Pair id: <pair token>. Answer with the JSON object that RUBRIC.md defines and nothing else.
```

- **Invalid reply.** If the reply is not valid JSON in the rubric's form, the same session gets one message with the
  parse error. If it is still invalid, one new session tries again. If that fails, that grader's grade for that pair is
  missing, and the other grader's grade stands alone (reported).
- **Humans (optional).** If the owner adds human graders before grading starts, they get the same packets, the same
  rubric and their own orders. Their grades are a secondary analysis and do not enter the primary merge.
- **Grading starts** only after all generation runs are finished, normalised, masked and blinded, and the commitment is
  pushed.

## 10. Merging grades and agreement

**Stricter score wins** (G1 and G2; a missing grade leaves the other):

| Item | Merge |
| --- | --- |
| (a) each check M1–M5 | PASS only if both graders give PASS. Score = number of merged PASS. |
| (b) errors | The larger count. Coverage: the smaller count. |
| (c) clarity | The lower score. |
| (d) defects | The larger count, for major and for minor separately. |
| (e) preference | Same answer: that answer. One "tie" and one side: tie. A against B: tie. |

**Agreement statistics** (G1 against G2, on the shown pairs), each with a 95 % bootstrap interval over pairs:

- mechanism checks: percent agreement and Cohen's kappa (PASS against not PASS), pooled and per check kind;
- mechanism score, errors, coverage and defect counts: Krippendorff's alpha (interval) and Spearman's rho;
- clarity: Cohen's kappa with quadratic weights;
- preference: Cohen's kappa over {A, B, tie}.

The result also gives the primary analysis for each grader alone, as a robustness check.

## 11. Analysis plan

Fixed in advance. The analysis script lands with the harness and is tested on synthetic data before run 1.

**Scores of a failed run.** Mechanism score 0, clarity 0, coverage 0. Errors = E_fail(q) = 1 + the largest error count
of any rendered run of that question in either arm (so a failure is always worse than any rendered output). Defects are
not defined for a failed run (the success rate reports failures). Preference: the rendered run wins; two failures tie.

**Primary metric.** The merged **mechanism score** (0 to 5) per run. For each question q and arm a, M(q, a) = the mean
over its runs. The paired difference is d(q) = M(q, Arm 1) − M(q, Arm 2).

**Primary test.** An exact two-sided sign test over the questions with d(q) ≠ 0 (binomial, p = 0.5), α = 0.05.
Effect size: the mean of d(q) over the 20 questions, with a 95 % percentile bootstrap interval (resample the 20
questions with replacement, 10 000 resamples, NumPy `default_rng(20261111)`).

**Secondary metrics** (an estimate and a 95 % interval each, by the same question-level bootstrap; they do not change
the verdict):

1. **Text errors per run** (merged): mean per arm and the paired difference per question. Sensitivity: only pairs where
   both runs rendered.
2. **Pairwise preference:** Arm 1 win rate = wins / (wins + losses) over the 60 pairs, with ties reported apart; the
   question-level winner (more pair wins) with a sign test over questions.
3. **Teaching clarity:** as the primary method.
4. **Visual defects:** mean major and minor counts per rendered run, per arm.
5. **Success rate:** rendered runs / all runs, per arm and per question.
6. **Coverage** of core key facts.
7. **Cost of the route:** tries used, wall time, and the CLI's `total_cost_usd` sum (a subscription equivalent, not a
   bill), per arm.
8. **Per category** table (descriptive only).
9. **Grader agreement** ([section 10](#10-merging-grades-and-agreement)) and the primary analysis per grader.
10. **Blinding check** ([section 8](#8-blinding)).
11. **Optional second generator:** the same plan, reported apart, with its own verdict line marked secondary.
12. **Human graders, if any:** the same plan, reported apart.

**Power.** With 20 questions and no ties, the sign test needs at least 15 of 20 questions to favour one arm
(two-sided p = 0.041). A small true difference will probably give "no conclusion". This is accepted and will be said.

**Stopping rule.** The design is fixed: all 120 runs (and the optional 80) are generated before any grading. There is no
interim look at outputs or scores, no early stop for success or futility, and no extra run. Usage limits or host faults
only pause the work; it continues from the next slot. If the runs are not complete 21 days after run 1, the result is
published as **incomplete** with every finished run, analysed by this plan over the questions that have all their runs.

## 12. Verdict and publication

| Verdict | Condition (primary test only) |
| --- | --- |
| **Win** for MartyGraphics | p < 0.05 and more questions have d(q) > 0 than d(q) < 0. |
| **Loss** for MartyGraphics | p < 0.05 and more questions have d(q) < 0 than d(q) > 0. |
| **No conclusion** | Any other outcome. The report gives the direction and the interval, and does not call it a win or a loss. |

Required statements: the report gives the primary verdict first, then every secondary metric, including those that go
against the verdict. If the interval of secondary metric 1 (text errors) excludes 0 in the direction against the primary
winner, the report says so in its first paragraph.

**Publication, whatever the result.** Within 7 days after grading ends, a pull request to this public repository adds
`benchmark/mechanisms-v1/results/` with: `RUNS.csv` (every run, failure and void), the raw grader JSON, the merged
table, the analysis output, `LOCK.json`, the seed and its commitment, run receipts, `FACT-CHECK.md`, and the blinded
artifact sets (as a GitHub release asset with SHA-256 hashes, if they are too large for the repository). The main
README links the result. A showcase or social post that uses a benchmark output links the full result and states the
verdict as defined here.

## 13. Amendments

Changes after this commit go in `AMENDMENTS.md` (dated, with the reason) and update [HASHES.txt](HASHES.txt) with the
old hashes kept in the amendment.

- **Before run 1, allowed:** fact-check corrections ([section 2](#2-fixed-inputs-the-lock-and-the-fact-check-gate)),
  the lock, the harness, grader model strings, and typing fixes that do not change meaning.
- **Before run 1, not allowed:** changes to the questions, to the scoring, to the primary metric or to the analysis.
- **After run 1:** only clarifications that cannot change any score, marked "no score effect".
- **After grading starts:** no change.
- A change that is needed but not allowed starts a new version (`mechanisms-v2`) with a new pre-registration. The v1
  result is still published.

## 14. Residual risks and known limits

1. **Arm signal** in the look of the renders ([section 8](#8-blinding)); measured, not removed.
2. **Shipped and worked examples.** Some questions are near shipped examples (see `nearShipped` in
   [QUESTIONS.json](QUESTIONS.json)): planetary sets, turbines, the turbofan. Marty's prompts or the component library may
   contain related worked examples. This can favour Arm 1 on those questions. The per-category table makes it visible.
3. **Unequal help in kind.** Arm 1 gets Marty's plan step and the engine's checks; Arm 2 gets screenshots of its own
   render, which Arm 1 does not get. The benchmark compares the two routes as products, at equal repair budgets.
4. **Same-family key.** A Claude model wrote the key facts and generates both arms. The fact-check gate uses two other
   model families to reduce shared blind spots.
5. **Small set.** 20 questions chosen by one designer. Low power for small effects (section 11).
6. **Non-determinism.** Model outputs vary between runs; 3 runs per question per arm reduce this.
7. **Graders are models.** Their errors are measured by agreement statistics; humans are optional.
8. **OCR.** `TEXT.txt` can miss or misread text; the rubric makes the images win.

## 15. Roles

- **Owner** (Collin Craig): approves the lock, may add human graders, reviews and merges pull requests.
- **Operator:** an agent session that runs the harness. It sees which arm made each run, so it never grades and never
  opens graded outputs before the seed is published.
- **Graders:** G1 and G2 (and humans, if added), blind as above.
- **Designer:** this pre-registration (Claude Opus 5.5, 2026-11-11). The designer did not run any part of the benchmark.
