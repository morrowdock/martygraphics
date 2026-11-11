# Harness: scoring and analysis (mechanisms-v1)

Status: **draft for review, 2026-11-11.** This is the primary scoring and grade-merge code that
[PROTOCOL.md, section 11](../PROTOCOL.md#11-analysis-plan) requires to be reviewed and hash-pinned in
[RUN-LOCK.json](../RUN-LOCK.json) before run 1. The lock is a draft until the review passes. The open choices are
in [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md). Nothing here has read or made a real benchmark output.

| File | Content |
| --- | --- |
| [score.py](score.py) | The section 10 merge of G1 and G2, the section 11 run scores (failed, graded, ungraded, N/A), M(q, a), d(q), the exact two-sided sign test, the section 12 verdict, the sensitivity analysis and the exploratory analyses listed in OQ-11. |
| [agreement.py](agreement.py) | Krippendorff's alpha (interval), Spearman's rho, Cohen's kappa (unweighted and quadratic) and percent agreement. |
| [tests/](tests/test_score.py) | Unit tests (every zero-denominator case for both arms, failed and ungraded runs, ties, the 15-of-20 boundary), agreement against published values, and an end-to-end test on synthetic grader files. |
| [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) | Where the protocol leaves a choice open: the options and the provisional choice. |

Python 3 standard library only. NumPy is needed only for the effect-size bootstrap interval that section 11
names (`default_rng(20261111)`). Without NumPy that interval is reported as not computed, and nothing else changes.

## Run the tests

From the repository root:

```
python3 -m unittest discover -s benchmark/mechanisms-v1/harness/tests
```

Without NumPy, one test (the bootstrap with NumPy) is skipped. All test data is synthetic; the end-to-end test uses
only the question ids and key facts of [QUESTIONS.json](../QUESTIONS.json).

## Score a result

From `benchmark/mechanisms-v1`, after grading ends and the seed and arm mapping are published:

```
python3 harness/score.py <input folder> --out <result.json> [--attest-within-21-days]
```

The input folder holds:

| Path | Content |
| --- | --- |
| `runs.csv` | `question,arm,run,status`: one row per run slot, with the final status `rendered` or `failed` (a void slot is the status of its last attempt; voids are logged elsewhere). |
| `pair-sides.csv` | `pair,A`: the arm shown as A in each preference packet (from the published arm mapping). Needed only for preference grades. |
| `grades/G1/score/<question>-r<r>-arm<a>.json` | G1's final stored score reply for that output, after unblinding. G2 likewise. No file: the grade is missing. |
| `grades/G1/preference/<question>-r<r>.json` | G1's final stored preference reply for that pair. G2 likewise. |

score.py refuses a grade for a failed run or an unknown slot, a slot listed twice, and a status other than
`rendered` or `failed`. A stored reply that is not in the rubric's form counts as missing and is listed
(OQ-03). It prints the verdict and writes the full result: every run's merged record, the per-grader values, M(q, a),
d(q), the test, the lists of ungraded and N/A outputs and every count.

`--attest-within-21-days` is the operator's statement that the design completed within 21 days after run 1 (OQ-07).
Without it, or with a missing run slot, or with more than 5 % of the rendered outputs ungraded, the result says
**descriptive results only**, gives no verdict, and reports what the primary test would have given.

## How the rules are implemented

- **Exact arithmetic.** Every score and mean is a `fractions.Fraction`, so a tie d(q) = 0 stays a tie. (A plain
  float mean of 1, 10/3 and 5/3 is 2.0000000000000004, and of 0, 1 and 5 is 2.0; a test keeps this case.) The JSON
  output gives each fraction as `{"exact": "p/q", "float": x}`.
- **Per-check merge.** PASS only if every judged grade is PASS; one judgment against CANNOT JUDGE or N/A gives the
  judgment; neither judged is unjudged, and both N/A is N/A. A missing grade leaves the other. The mechanism score is
  5 × PASS / judged, from the merged checks (never from the two graders' scores), and N/A when no check is judged.
- **N/A and ungraded leave the means.** A run whose mechanism score is N/A, and an ungraded output, are listed, are
  never scored 0 and never count as a pass; M(q, a) is the mean of the other runs, and undefined when none is left.
- **Failed runs.** Mechanism 0, clarity 0, coverage 0, errors E_fail(q), defects undefined.
- **The test.** Exact two-sided binomial sign test over the defined d(q) that are not 0, p as a fraction, win or loss
  only with p < 0.05. `NEAR_SHIPPED` is checked against QUESTIONS.json by the end-to-end test.
