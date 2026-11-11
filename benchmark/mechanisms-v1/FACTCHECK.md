# Fact-check receipt: mechanisms-v1 key version 2

Date: 2026-11-11. Status: **applied** to [QUESTIONS.json](QUESTIONS.json) (key version 2), [RUBRIC.md](RUBRIC.md) and
[GRADER-QUESTIONS.json](GRADER-QUESTIONS.json). Baseline: key version 1 at commit `0de70ed` (pre-registration; `bd2239e` after the rebase onto `ca22181`).

## The two checks

| Check | Model | Setup | VERIFIED | PLAUSIBLE | AMBIGUOUS | SOURCE-MISMATCH | WRONG |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| Sol | `gpt-6.1-sol` | with the designer's sources; all 22 cited URLs requested; Norton 9.8 and Uicker 8.15 read | 59 | 6 | 31 | 5 | 0 |
| Gemini | `gemini-4-argon` | blind: the question file without sources | 93 | 0 | 7 | — | 1 |

Both checks also audited the 100 mechanism checks. The coordinator merged them (stricter label wins: WRONG >
SOURCE-MISMATCH = AMBIGUOUS > PLAUSIBLE > VERIFIED; where both give a fix, combine; where they conflict, use the more
permissive rule that is still physically correct).

The raw reports are not committed (they hold long quotations). Their SHA-256 hashes:

| File | SHA-256 |
| --- | --- |
| FACTCHECK-SOL.md | `6e39ccf3b39ebc0860bc1f9882b552b58b21199a468cc188881fa4a36d17661b` |
| FACTCHECK-GEMINI.md | `2655ab796092f8ebb7d77c501509940fac24838cbd2fb22b190bae96ddc81a75` |
| MERGED-CORRECTIONS.md (coordinator) | `dc4eaec34a2510d5ed58904d9d62534c43db36b4f99c6caf3a3e53566893e69b` |

## Merged result

Merged labels of the 101 version-1 facts: AMBIGUOUS 31, AMBIGUOUS+SOURCE-MISMATCH 1, PLAUSIBLE 6, SOURCE-MISMATCH 4, VERIFIED 58, WRONG 1.
So 43 facts needed an action. All 43 are corrected or re-sourced. The question texts did not change.

## Design rule (section A) and other sections

| Item | Status | How |
| --- | --- | --- |
| A.1 Do not change the 20 prompts | applied | The `question` strings are byte-identical to key version 1 (checked by the apply script). |
| A.2 Per-question accepted variants | applied | Every question has `conventional` and `acceptedVariants`; 9 questions list variants (MECH-06, 08, 09, 12, 13, 17, 18, 19, 20). |
| A.3 Conditional facts, N/A grade, variant facts | applied | Facts have `appliesTo` (`all`, `conventional` or variant ids); 6 kept-text facts were made conditional; 7 variant facts added. RUBRIC.md defines N/A (leaves numerator and denominator). Check clauses name their configuration inline. The per-fact field `acceptedVariants` of version 1 is renamed `acceptedWordings`, so it does not clash with the per-question list. |
| A.4 Six global judging fixes | applied | RUBRIC.md, "Judging limits" (adapted to the 10 fps strip) and the clause rule; a "Large jumps" rule tells graders to answer CANNOT JUDGE for undersampled motion (the grader validation showed confident wrong directions beyond the limits). |
| B WRONG (1) | applied | MECH-10 K2 rewritten (lift along the line of motion; knife-edge, roller, flat-faced and offset followers). |
| B AMBIGUOUS in both (6) | applied | MECH-01 K3, MECH-02 K3, MECH-06 K4, MECH-07 K2, K3, MECH-17 K4: both fixes combined. |
| B AMBIGUOUS, Gemini only (1) | applied | MECH-08 K3: tangency only for the crank-and-slotted-lever; Whitworth stated. |
| B AMBIGUOUS, Sol only (25) | applied | Sol's corrected wording for each, made conditional where needed. MECH-18 K1: the 4 to 13 window is removed; example numbers must name engine, date and condition. |
| B SOURCE-MISMATCH (4 more) | applied | MECH-07 K1 and K4: FIRGELLI replaced by Illinois, Rutgers DIMACS and Wikipedia sources. MECH-16 K1 and K2: NPTEL Lecture 26. MECH-01 K3 (also SOURCE-MISMATCH): Omni removed; CMU, METU and Norton 9.8. |
| B PLAUSIBLE (6) | applied | MECH-06 K5 and MECH-20 K1, K2, K3, K5: a second independent source from the Gemini check (now `verified-web`). MECH-18 K5: no second source; marked `single-source`; the 70 to 90 % window and the take-off percentage are removed. |
| C Hidden correct answers (8 items) | applied | All listed configurations are accepted variants (section A.2), with variant facts where the reports describe them. |
| D Mechanism checks | applied | All 46 Sol R cells and all 12 Gemini items; 57 checks revised (with 3 Sol D clarifications: MECH-08 M4, MECH-13 M4, MECH-14 M4). Each check records Sol's Y/D/R and the Gemini item. |
| D.11 MECH-18 M5 | applied (second option) | "Concentric shafts" is NOT SHOWN when only one shaft is shown; with the clause rule, M5 is then graded on the flow clause. |
| E Key version, receipt | applied | `keyVersion` 2 and `keyHistory` in QUESTIONS.json; this file; CHANGELOG. |
| E Grader validation | still valid | It tests the perception of speed, direction, timing and flicker in the frame strip, not the key text. |
| Open: textbook pages | not applied (recorded) | No page-level verification of the textbook citations, except Norton 9.8 and Uicker 8.15 (read by Sol). Three variant facts (MECH-06 K7, MECH-20 K6, K7) have no inspected web source (`fact-check-only`, core: false). |

## Facts: every action

| Question | Fact | Sol | Gemini | Merged | Action | appliesTo | Check label |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MECH-01 | K1 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-01 | K2 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-01 | K3 | SOURCE-MISMATCH | AMBIGUOUS | AMBIGUOUS+SOURCE-MISMATCH | corrected | all | verified-web |
| MECH-01 | K5 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-02 | K2 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-02 | K3 | AMBIGUOUS | AMBIGUOUS | AMBIGUOUS | corrected | all | verified-web |
| MECH-02 | K5 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-04 | K1 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-05 | K3 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-05 | K5 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-06 | K1 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | conventional | verified-web |
| MECH-06 | K2 | VERIFIED | VERIFIED | VERIFIED | made conditional | conventional | verified-web |
| MECH-06 | K3 | VERIFIED | VERIFIED | VERIFIED | made conditional | conventional | textbook-only |
| MECH-06 | K4 | AMBIGUOUS | AMBIGUOUS | AMBIGUOUS | corrected | conventional | verified-web |
| MECH-06 | K5 | PLAUSIBLE | VERIFIED | PLAUSIBLE | corrected | all | verified-web |
| MECH-06 | K6 | — | — | — | added (variant) | reversing-motor | verified-web |
| MECH-06 | K7 | — | — | — | added (variant) | rack-drive | fact-check-only |
| MECH-07 | K1 | SOURCE-MISMATCH | VERIFIED | SOURCE-MISMATCH | corrected | all | verified-web |
| MECH-07 | K2 | AMBIGUOUS | AMBIGUOUS | AMBIGUOUS | corrected | all | verified-web |
| MECH-07 | K3 | AMBIGUOUS | AMBIGUOUS | AMBIGUOUS | corrected | all | verified-web |
| MECH-07 | K4 | SOURCE-MISMATCH | VERIFIED | SOURCE-MISMATCH | corrected | all | verified-web |
| MECH-08 | K3 | VERIFIED | AMBIGUOUS | AMBIGUOUS | corrected | all | verified-web |
| MECH-09 | K2 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | conventional | verified-web |
| MECH-09 | K3 | VERIFIED | VERIFIED | VERIFIED | made conditional | conventional, desmodromic | verified-web |
| MECH-09 | K4 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | conventional, desmodromic | verified-web |
| MECH-09 | K6 | — | — | — | added (variant) | desmodromic | verified-web |
| MECH-09 | K7 | — | — | — | added (variant) | two-stroke-poppet | verified-web |
| MECH-10 | K2 | AMBIGUOUS | WRONG | WRONG | corrected | all | verified-web |
| MECH-11 | K3 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-12 | K2 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-12 | K4 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-14 | K2 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-14 | K3 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-15 | K3 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-15 | K5 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-16 | K1 | SOURCE-MISMATCH | VERIFIED | SOURCE-MISMATCH | corrected | all | verified-web |
| MECH-16 | K2 | SOURCE-MISMATCH | VERIFIED | SOURCE-MISMATCH | corrected | all | verified-web |
| MECH-16 | K3 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-17 | K4 | AMBIGUOUS | AMBIGUOUS | AMBIGUOUS | corrected | all | verified-web |
| MECH-17 | K5 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-18 | K1 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-18 | K2 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-18 | K3 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-18 | K4 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-18 | K5 | PLAUSIBLE | VERIFIED | PLAUSIBLE | corrected | all | single-source |
| MECH-19 | K1 | VERIFIED | VERIFIED | VERIFIED | made conditional | conventional | textbook-only |
| MECH-19 | K3 | VERIFIED | VERIFIED | VERIFIED | made conditional | conventional | textbook-only |
| MECH-19 | K4 | VERIFIED | VERIFIED | VERIFIED | made conditional | conventional | textbook-only |
| MECH-19 | K6 | — | — | — | added (variant) | internal-gear | verified-web |
| MECH-20 | K1 | PLAUSIBLE | VERIFIED | PLAUSIBLE | corrected | conventional | verified-web |
| MECH-20 | K2 | PLAUSIBLE | VERIFIED | PLAUSIBLE | corrected | conventional | verified-web |
| MECH-20 | K3 | PLAUSIBLE | VERIFIED | PLAUSIBLE | corrected | conventional | verified-web |
| MECH-20 | K4 | AMBIGUOUS | VERIFIED | AMBIGUOUS | corrected | all | verified-web |
| MECH-20 | K5 | PLAUSIBLE | VERIFIED | PLAUSIBLE | corrected | all | verified-web |
| MECH-20 | K6 | — | — | — | added (variant) | deep-well | fact-check-only |
| MECH-20 | K7 | — | — | — | added (variant) | force-pump | fact-check-only |

The other 52 facts are VERIFIED in both checks and unchanged (they gain `appliesTo: all` and the fact-check record).

## Mechanism checks: every revision

| Question | Revised checks (Sol label / Gemini item) |
| --- | --- |
| MECH-01 | M1 (R), M2 (R), M4 (R), M5 (R) |
| MECH-02 | M2 (R), M3 (R), M4 (D/G1) |
| MECH-03 | M1 (R), M5 (R) |
| MECH-04 | M2 (R), M3 (R/G2), M4 (D/G2), M5 (R) |
| MECH-05 | M3 (D/G3), M4 (R) |
| MECH-06 | M1 (R), M2 (R), M3 (R), M4 (D), M5 (R) |
| MECH-07 | M3 (R/G4), M4 (R), M5 (R) |
| MECH-08 | M1 (R), M2 (R), M3 (R/G5), M4 (D) |
| MECH-09 | M1 (R/G6), M2 (R/G6), M3 (D), M4 (R/G6), M5 (R) |
| MECH-10 | M4 (R/G7), M5 (R) |
| MECH-11 | none |
| MECH-12 | M3 (R/G8), M5 (R) |
| MECH-13 | M4 (D), M5 (R) |
| MECH-14 | M3 (R), M4 (D) |
| MECH-15 | M4 (R/G9) |
| MECH-16 | M3 (R/G10), M4 (R/G10), M5 (R) |
| MECH-17 | M1 (R), M3 (R), M4 (R) |
| MECH-18 | M2 (R), M3 (R), M4 (R), M5 (Y/G11) |
| MECH-19 | M3 (D), M4 (R/G12), M5 (R) |
| MECH-20 | M1 (R), M3 (D), M4 (R) |
