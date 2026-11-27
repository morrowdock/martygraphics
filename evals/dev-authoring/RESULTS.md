# Dev authoring eval: results (2026-11-26)

**Author and grader designer: Claude Opus 5.5 (`claude-opus-5-5`), the same model, in one session.** No paid API,
no other model, no Mac. [FREEZE.json](FREEZE.json) holds the SHA-256 of the requests, specs and contract and the
reported freeze time (2026-11-27 03:02 UTC), before authoring. The hashes prove only that the checked-in files are
byte-identical to the frozen ones. With the timestamp they record the reported order; they do not prove it, and
git history does not either (an intermediate commit of the freeze was declined in that session).

## Starting point: the public benchmark summary

The published test ([showcase](../../docs/SHOWCASE.md#from-a-prompt), [README](../../README.md#honesty-and-limits))
covered Solid 3D mechanisms, not 2D scenes. Claude Haiku 5.5 got 40 of 40 in-scope questions accepted within three
repairs, but only 29 of 40 were fully correct in mechanics, and 4 of 50 explanations had a critical error. Its
failure categories:

1. **Silent substitution.** Unsupported parts (bevel, worm, crown gears) were swapped for flat spur gears without
   saying so.
2. **Numbers in text that the model did not have.** Captions quoted values that differ from the solved model.
3. **Conventions the docs did not show.** Features were skipped or misused where the docs gave no clear convention.

Validity was never the bottleneck (40 of 40 accepted); correctness was. This eval targets the same three
categories for 2D scenes and the ML kit. A pie chart tests substitution (M08). Every request has number checks.
Directions, anchors, mappings and step order test conventions.

## Raw observations (one author, not a measured change)

The same author wrote both runs, so these rows are observations of one author, not a comparison of guidance.

| | Baseline guidance | Improved guidance |
| --- | --- | --- |
| Mechanically correct | **39 / 40** | **40 / 40** |
| Checks passed | 214 / 215 | 215 / 215 |
| Valid on the first try | 40 / 40 | 40 / 40 |
| Repairs used | 0 | 0 |
| Lint findings on the scene outputs (32 scenes, 2 of them template scenes the lint skips) | 4 warnings and 6 review cues, in 7 scenes | 0 |

| Domain | Baseline | Improved |
| --- | --- | --- |
| Physics (12) | 12 | 12 |
| Math (10) | 10 | 10 |
| CS (10) | 9 | 10 |
| ML kit (8) | 8 | 8 |

| Check category | Baseline | Improved |
| --- | --- | --- |
| items | 11 / 11 | 11 / 11 |
| geometry | 40 / 40 | 40 / 40 |
| direction | 17 / 17 | 17 / 17 |
| magnitude | 10 / 10 | 10 / 10 |
| numbers | 45 / 45 | 45 / 45 |
| data | 68 / 68 | 68 / 68 |
| order | 23 / 24 | 24 / 24 |

The one baseline failure is **C06** (bubble sort). Step 0 applied the first swap, so the unsorted input
`5, 1, 4, 2, 8` was never shown. The engine applies step 0's edits before the first frame, and the baseline docs
do not say so. The improved guide states it, and the new lint flags it (`step0.edits`).

**What this run does and does not show.** Raw observations: the baseline run had 39 of 40 requests mechanically
correct (214 of 215 checks) and the improved-guidance run 40 of 40 (215 of 215); both were valid on the first try
and used no repairs. The author was the same model in the same session, it designed the specs, and in the second
run it knew the baseline failure. The baseline was already at 39 of 40, so the two runs cannot show whether the
guidance changes accuracy. That needs independent authors; see the follow-ups.

## Author-independent measures

Every number in this section is recomputed from checked-in files by `python3 tools/inventory.py` (in this
directory) and asserted by `tools/test_inventory.py`.

| Measure | Baseline (main 5e4952e) | This branch |
| --- | --- | --- |
| Matches to 17 text probes selected from the new guide ([probes](inventories/conventions.json)) | 1 / 17 | 17 / 17 |
| Scene refusal reasons with extra text ([160 sample tokens](inventories/scene-reasons.json)) | 3, as details, not fix hints (`input.too-large`, `json`, `template.unknown`) | 160 with a fix hint |
| ML kit refusal reasons with a fix hint (every `MGMLReason`) | 0 / 58 | 58 / 58 |

The [probe list](inventories/conventions.json) gives each convention the 40 correct answers depend on, its text
patterns and notes on related baseline text (file and line at 5e4952e). The patterns follow the new guide's
wording, so the current prose matches 17 of 17 by construction. In the 5e4952e prose only the table-anchor probe
matches (PROTOCOL.md:178). A probe that does not match is not proof that the baseline lacks the convention: it
may be stated in other words or shown only by an example, and the notes do not claim to be complete.

The [reason sample](inventories/scene-reasons.json) has 160 tokens: the 58 static `MGError` literals in
`MGParser.swift`, `json`, `input.too-large` and `scene.missing`, the item missing and unknown families of the 19
kinds, every kind–field family, and ten dynamic forms with one sample each. An earlier draft of this file said 148
tokens; that number could not be reproduced and is replaced by 160. The baseline validator printed extra detail
text for 3 of them (`SceneValidator.swift:153`, `:167` and `:172` at 5e4952e).

**Lint on the frozen baseline outputs.** `tools/scene_lint.py` gives 10 findings in 7 of 32 scenes: 4 warnings
(all in M09) and 6 review cues. It skips the 2 template scenes (C02, C03) and says so. Read by hand:

- C06 `step0.edits` (review cue): the spec failure the grader caught.
- M09 `display.rounding` (4 warnings): the chart draws 0.12 and 0.38 while the narration says 0.375. This is a
  number the board does not show, the same class as public category 2. No spec checks it.
- P03, P11 `line.ground.side` (review cues): a ceiling drawn left to right hatches into the scene.
- C04 `step0.edits` (review cue): the request asks for the empty stack first, and step 0's edit means it is never
  shown.
- C08 `step0.edits` (review cue): step 0 makes an intentional first insertion; not a defect.
- C05 `step0.edits` (review cue): harmless; not a defect.

That is five defects in total, four of them outside the specs (M09, P03, P11, C04), and C06, a spec failure the
grader caught. C05 and C08 are cues that need no change. The improved-guidance outputs give no findings.

**Grader validation.** `tools/test_grader.py` injects 29 known mistakes into passing baseline scenes, one per
check family (wrong normal-force angle, wrong length ratio, edges visible too early, BFS order swapped and so on).
Each must fail its targeted check, and the unmutated scene must pass it. All do.

## Limits, stated plainly

- **Same model as author and grader designer.** The author knew the specs, having written them; knew the
  parser's validation rules (`MGParser.swift` was read before the baseline, which inflates first-try validity);
  and, in the improved pass, knew the baseline failure. "Fresh pass" means the baseline files were not reopened
  or copied; memory was not erased.
- **Rendering conventions were read only after the baseline pass**, so the baseline's convention guesses were
  genuine. The natural guesses (counter-clockwise degrees, bottom-left incline vertex) happened to match the engine.
- **The guide's worked examples share patterns with some eval items** (incline forces, a plot marker, an array
  walkthrough, a relinked list, a pie). Numbers and scenarios differ, but this can raise any author's improved
  score.
- **The repair loop was never exercised**: 0 refusals in both runs. Hint quality is covered only by unit tests
  (coverage, and a shared corpus of exact outputs that Python asserts here and Swift asserts on a Mac), not by
  measured repairs.
- **Python mirrors are drafts.** The scene checker is the copied `scene_v1_check.py`; `tools/ml_check.py` mirrors the
  ML kit without PNG kinds. Swift `MGParser` and `MGMLKit` stay authoritative. **All Swift changes are unbuilt and
  untested here, pending Mac verification.**
- The ML items are easy for this author; their checks mostly confirm parameters that the kit computes from.

## Follow-ups

1. **Independent authors, A/B.** Run Codex, and Claude Haiku 5.5 (the published benchmark's model), on all 40
   requests with the baseline bundle, then with the improved bundle. Use fresh processes, do not show them
   `specs.json`, and do at least 3 runs per arm for variance. Steps are in the [README](README.md#independent-author-run).
2. **Mac verification**: `swift test` for the package and for `tools/SceneValidator`, the new `--hints` goldens,
   the shared hint corpus (`RepairHintCorpusTests`, `MLRepairHintCorpusTests`) and the ML mirror.
3. **A harder v2 set written by someone other than the author**: multi-object scenes, camera, 3D, more
   unsupported-feature requests.
4. **Solid 3D**, where the public failures live: the same checklist and hint approach for constraint reasons
   such as `constraint.gearMesh.phase`, and a disclosure check for substituted gear types.
