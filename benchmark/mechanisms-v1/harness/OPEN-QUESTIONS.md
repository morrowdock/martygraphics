# Open questions: mechanisms-v1 harness

Status: **open, 2026-11-11.** These are places where [PROTOCOL.md](../PROTOCOL.md) and [RUBRIC.md](../RUBRIC.md) leave
a choice to the scoring code. The harness does not choose silently. Each item names the options and the
**provisional** choice in [score.py](score.py) (the `DECISIONS` table, or the named function). This file changes no
question, key fact, check, prompt, rubric or protocol text. The owner's review decides every item before
[RUN-LOCK.json](../RUN-LOCK.json) stops being a draft. If an answer needs a protocol change, it goes to
`AMENDMENTS.md` under section 13 (before run 1, only what section 13 allows) or to a `mechanisms-v2`.

Items OQ-01 to OQ-04 can change a run score. OQ-05 can change only the reported interval. The other items change
reporting or input handling only; none can change the primary verdict.

## Can change a score

**OQ-01. Which core facts are "applicable" in one grader's coverage fraction?** Section 10 (b) divides covered
applicable core facts by applicable core facts. RUBRIC.md has the grader name a configuration and also list
`notApplicableFacts`. The two can disagree.

- A (provisional, `DECISIONS["applicableCoreFacts"] = "configuration"`): the core facts whose `appliesTo` holds `all`
  or the configuration the grader names (`unclear` or an unknown name counts as `conventional`, as the rubric says).
  The grader's `notApplicableFacts` list is checked against it, and a difference is a warning. Section 10's sentence
  "Every configuration in the key has at least 2 applicable core facts" only guards the denominator under this
  reading.
- B (`"grader-list"`): all core facts minus the ones the grader lists in `notApplicableFacts`. A grader could then
  make the denominator 0 by listing every core fact.
- C: the intersection of A and B.

In every option only applicable core facts enter the numerator. A non-core, unknown or N/A id in `coveredFacts` is
ignored and raises a warning.

**OQ-02. E_fail(q) when question q has no graded output in either arm** (all 6 runs failed or ungraded). Section 11:
1 + the largest merged error count of any graded output of q, and that set is empty.

- A (provisional, `efailWithoutGradedOutput = 1`): the largest count over no output is 0, so E_fail(q) = 1.
- B (`None`): E_fail(q) is undefined, and those failed runs leave the error means (reported).

This affects only the exploratory error analyses, never the mechanism score.

**OQ-03. What is "valid JSON in the rubric's form" (section 6), and what does a stored invalid reply mean?** The
grading runner must use the same validator for its retry loop (one fix-up message, then up to 2 new sessions).

- Form (provisional, `validate_score_reply`): an object with every key the rubric's example shows (`question`,
  `output`, `configuration`, `mechanism`, `errors`, `unsure`, `coveredFacts`, `notApplicableFacts`, `clarity`,
  `clarityReason`, `defects`) with the right JSON types; `question` equals the packet's question id; `M1` to `M5`
  each one of the five results, with `CANNOT JUDGE` only on `M3` and `M4`; every error has a type `K`, `N`, `L` or
  `O`; every defect has a type `D1` to `D6` and a severity `major` or `minor`; `clarity` an integer from 1 to 5 (not
  `4.0`, not `true`). **Not** required: the `evidence` texts of rule 5, the error and defect `time` and text fields.
  Extra keys are allowed. Contradictions (a fact both covered and N/A, unknown fact ids) are warnings, not invalid.
  The alternative is a stricter form that also requires evidence for every FAIL, CANNOT JUDGE, error and defect.
- Stored invalid reply (provisional, `invalidStoredReply = "missing"`): the final stored reply of a grader that is
  still invalid is a missing grade, as section 6 says after the third session, and it is listed in `invalidGrades`.
  The alternative is to stop the analysis, so that a runner that skipped its retries cannot pass unnoticed.
- The output token in a reply is not checked against the seed (score.py works on unblinded file names). The
  alternative is to require the seed and recompute it (see OQ-09).

**OQ-04. A check answered N/A while the grader names the conventional configuration.** RUBRIC.md allows N/A only when
the explainer shows an accepted variant, and every check of a question without variants applies.

- A (provisional): take the answer as given (N/A leaves the numerator and the denominator) and report a warning.
- B: report it as unjudged instead of N/A. The score is the same as in A; only the reported counts differ.
- C: treat the reply as not in the rubric's form (OQ-03), which starts the retry loop.

## Can change only the reported interval

**OQ-05. The effect-size bootstrap (section 11).** "Resample the questions with replacement, 10 000 resamples, NumPy
`default_rng(20261111)`" leaves open:

- the draw (provisional: `rng.integers(0, n, size=(10000, n))`; alternatives `rng.choice(values, size=(10000, n))`
  or 10 000 separate calls, each a different stream of numbers);
- the percentile method (provisional: `np.percentile(means, [2.5, 97.5])` with NumPy's default linear method);
- the population (provisional: the defined d(q), zeros included; it is the same set as the reported mean);
- one generator per analysis (provisional: a fresh `default_rng(20261111)` for each of the primary analysis, the
  sensitivity analysis and each exploratory analysis) or one shared stream in a fixed order;
- NumPy itself. It is the only non-standard-library dependency. Without it, score.py reports the interval as "not
  computed" and every other number is the same. RUN-LOCK.json must pin the NumPy version used for the result.

## Reporting and input handling only

**OQ-06. Bootstrap intervals for the agreement statistics (section 10).** "Each with a 95 % bootstrap interval over
items" names no seed, no resample count and no item for the check statistics (output or check). Provisional: the point
estimates are computed and the intervals are reported as not computed. Options: the section 11 settings
(10 000, `default_rng(20261111)`) with outputs as items, or a new stated seed.

**OQ-07. The completed-design condition (section 11).** The 21-day limit, "every grading call made under section 6"
and a withdrawn model cannot be read from the grade files. Provisional: the verdict is withheld unless the operator
passes `--attest-within-21-days`; missing run slots and more than 5 % ungraded rendered outputs are checked from the
data (exactly 5 % still allows the verdict: "more than"). Option: a dated record file (run 1 start, last grading call,
grading-call log) that score.py checks instead of an attestation flag.

**OQ-08. The merged result of two judged checks that are not both PASS.** Section 10 says "stricter wins", but does not
order FAIL and NOT SHOWN. Only PASS against not PASS enters the score. Provisional: the merged state is `NOT PASS`, and
both raw grades are kept per grader. Option: FAIL is stricter than NOT SHOWN. No score effect.

**OQ-09. The HMAC inputs of section 8** (for the packer, not for score.py). "HMAC-SHA256(seed, ...)" does not say
whether the key is the 64-character hex string (as ASCII bytes) or the 32 raw bytes, and does not name the message
encoding (UTF-8 is the obvious one). score.py takes the arm sides from the committed mapping (`pair-sides.csv`), so
it is not affected. The packer must fix one choice and publish it with RUN-LOCK.json.

**OQ-10. HASHES.txt says "SHA-256 of every other file in this folder."** This pull request adds `harness/`,
`RUN-LOCK.json` and this file to the folder, and does not edit HASHES.txt, which is a registration file. `shasum -a 256
-c HASHES.txt` still passes. RUN-LOCK.json pins the harness files. Options: leave HASHES.txt as the registration
record (provisional), or record an `AMENDMENTS.md` entry that says the sentence means the registration files.

**OQ-11. Exploratory analyses that are not implemented yet.** Section 11 says "the analysis script lands with the
harness and is tested on synthetic data before run 1". This pull request implements the primary analysis, the
sensitivity analysis, per-arm counts (CANNOT JUDGE, unjudged and N/A per check; configurations and their agreement;
ungraded, failed, mechanism N/A and coverage N/A lists), success rates, pooled per-arm means, question-level
differences for errors, clarity and coverage, preference win rates (graded, and with automatic preferences), the
primary analysis for each grader alone and the agreement point estimates. **Not yet:** errors only on pairs where
both rendered (1), the question-level winner by pair wins (2), question-level defect means (4), per-question success
rates (5), cost of the route (8), the per-category table (9), the blinding check and its binomial test (11), and the
optional generator and human graders (12). Options: a follow-up pull request before run 1 (a separate analysis
module, so that the pinned primary code stays unchanged), or this pull request. Coverage (6) is a mean of per-run
fractions here; the alternative is a pooled ratio (all covered over all applicable).

**OQ-12. No question with a defined d(q).** Provisional: p = 1 (vacuously "every defined d(q) is 0"), mean
undefined, no conclusion. Section 11 would make such a result descriptive in practice.
