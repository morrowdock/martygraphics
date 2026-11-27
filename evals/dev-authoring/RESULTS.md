# Dev authoring eval: results (2026-11-26)

**Author and grader designer: Claude Opus 5.5 (`claude-opus-5-5`), the same model, in one session.** No paid API,
no other model, no Mac. Specs frozen before authoring ([FREEZE.json](FREEZE.json), 2026-11-27 03:02 UTC). An
intermediate commit of that freeze was declined in this session, so only the recorded hashes and the timestamp
show the order; git history alone does not prove it.

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

## Scores

| | Baseline guidance | Improved guidance |
| --- | --- | --- |
| Mechanically correct | **39 / 40** | **40 / 40** |
| Checks passed | 214 / 215 | 215 / 215 |
| Valid on the first try | 40 / 40 | 40 / 40 |
| Repairs used | 0 | 0 |
| Lint warnings on the scene outputs (32 scenes) | 10, in 7 scenes | 0 |

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

**What this run does and does not show.** For this author the eval is at its ceiling: 39 of 40 before any change.
A one-request gain from a fully informed author is not evidence of a substantial improvement, so read the
before → after row as a consistency check, not as a measured gain. The improvements were designed to measure on
an independent author; see the follow-ups.

## Author-independent measures

| Measure | Baseline | Improved |
| --- | --- | --- |
| Conventions the 40 correct answers depend on that the docs state (17 probes) | 1 | 17 |
| Scene refusal reasons with a fix hint (148 tokens: every static `MGParser` reason and every kind–field family) | 3 (`json`, `template.unknown`, `input.too-large`, as details) | 148 |
| ML kit refusal reasons with a fix hint | 0 / 58 | 58 / 58 |

The convention probes are text patterns written against the new guide, so the improved column is 17 by
construction. The baseline column is the informative one: 16 of the 17 conventions were not stated. Plot and bars
anchors and edge direction can be inferred from worked examples. The vector angle sense, incline orientation,
step timing and `show` semantics cannot.

**New guards on the frozen baseline outputs.** `tools/scene_lint.py` gives 10 warnings in 7 of 32 scenes:

- C06 `step0.edits`: the spec failure.
- M09 `display.rounding`: the chart draws 0.12 and 0.38 while the narration says 0.375. This is a number the board
  does not show, the same class as public category 2. No spec checks it.
- P03, P11 `line.ground.side`: a ceiling drawn left to right hatches into the scene.
- C04, C08 `step0.edits`: the empty starting state is never shown. Minor.
- C05 `step0.edits`: harmless, a false positive.

That is 1 spec failure, 5 real defects the specs did not check, and 1 false positive.

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
  (coverage, Swift–Python drift), not by measured repairs.
- **Python mirrors are drafts.** The scene checker is the copied `scene_v1_check.py`; `tools/ml_check.py` mirrors the
  ML kit without PNG kinds. Swift `MGParser` and `MGMLKit` stay authoritative. **All Swift changes are unbuilt and
  untested here, pending Mac verification.**
- The ML items are easy for this author; their checks mostly confirm parameters that the kit computes from.

## Follow-ups

1. **Independent authors, A/B.** Run Codex, and Claude Haiku 5.5 (the published benchmark's model), on all 40
   requests with the baseline bundle, then with the improved bundle. Use fresh processes, do not show them
   `specs.json`, and do at least 3 runs per arm for variance. Steps are in the [README](README.md#independent-author-run).
2. **Mac verification**: `swift test` for the package and for `tools/SceneValidator`, the new `--hints` goldens,
   and the Swift–Python parity of the hints and the ML mirror.
3. **A harder v2 set written by someone other than the author**: multi-object scenes, camera, 3D, more
   unsupported-feature requests.
4. **Solid 3D**, where the public failures live: the same checklist and hint approach for constraint reasons
   such as `constraint.gearMesh.phase`, and a disclosure check for substituted gear types.
5. **Policy.** CONTRIBUTING asks not to submit "generation instructions". The maintainer should decide whether
   `docs/AUTHORING.md` (format conventions, checklist and examples, not a prompt) belongs in the public repo.
