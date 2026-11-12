# Harness: scoring and analysis (mechanisms-v1)

Status: **draft for review, 2026-11-11.** This is the primary scoring and grade-merge code, and the analysis plan,
that [PROTOCOL.md, section 11](../PROTOCOL.md#11-analysis-plan) requires to be reviewed and hash-pinned in
[RUN-LOCK.json](../RUN-LOCK.json) before run 1. The lock is a draft until the review passes. The decisions on the
protocol's open points are in [AMENDMENTS.md](../AMENDMENTS.md); the options are in
[OPEN-QUESTIONS.md](OPEN-QUESTIONS.md). Nothing here has read or made a real benchmark output.

| File | Content |
| --- | --- |
| [score.py](score.py) | Reads and checks the input, merges G1 and G2 (section 10), computes the run scores, M(q, a), d(q), the sign test, the verdict and its conditions, and every analysis of sections 10 and 11. |
| [rubric_form.py](rubric_form.py) | The one validator of "valid JSON in the rubric's form", plus the section 6 attempt rule (`call_status`, and `next_step` for the grading runner). |
| [blinding.py](blinding.py) | Section 8 tokens, sides and the commitment, with the A-09 encoding. |
| [agreement.py](agreement.py) | Krippendorff's alpha (interval), Spearman's rho, Cohen's kappa (unweighted and quadratic) and percent agreement, plus their bootstrap forms. |
| [tests/](tests/test_score.py) | Synthetic tests only (see below). |

**Requirements:** Python 3.11 or later, and **NumPy at the version that RUN-LOCK.json pins** (`harness.numpy`,
2.5.4). Section 11 names NumPy `default_rng(20261111)` for the intervals, so score.py refuses to report without that
version. Everything else is the standard library.

## Run the tests

From the repository root:

```
python3 -m venv .venv && .venv/bin/pip install numpy==2.5.4
.venv/bin/python -m unittest discover -s benchmark/mechanisms-v1/harness/tests
```

The tests cover:

- the merge;
- every zero-denominator case for both arms;
- failed, ungraded and all-failed designs;
- ties and the 15-of-20 boundary;
- the validator, using the rubric's own example replies;
- the attempt rule;
- the record and timing conditions;
- the blinding vectors;
- agreement against published values;
- an end-to-end run through the command line on the real key's 20 question ids.

The fixtures are built by [tests/support.py](tests/support.py), and every fixture reply passes the validator.

## Score a result

From `benchmark/mechanisms-v1`, after grading ends and the seed and mapping are published:

```
python3 harness/score.py <input folder> --out <result.json>
```

| Input file | Content |
| --- | --- |
| `runs.csv` | `question,arm,run,status,startedUTC,endedUTC,tries,costUsd`. There is one row per run slot, with the final status `rendered` or `failed` (a void slot gives its last attempt). Times are ISO 8601 with a zone, for example `2026-12-01T10:00:00+00:00`. |
| `BLINDING-SEED.txt`, `BLINDING-COMMITMENT.txt` | The seed (64 lowercase hex characters) and its commitment. They are checked against each other. |
| `output-tokens.csv` | `output,token`: the published token of every rendered output. |
| `pair-sides.csv` | `pair,token,A`: the token of every pair with two rendered outputs, and the arm shown as A. |
| `RECORD.json` | The dated completion and call record (below). |
| `replies/...` | The exact text of every grader reply that the record names. |

Both mapping files must equal what the seed gives; a missing row, an extra row or a duplicate row (conflicting or
not) is refused.

`RECORD.json`:

```json
{"kind": "mechanisms-v1.record/1",
 "commitmentPushedUTC": "2026-12-04T09:00:00+00:00",
 "withdrawnModels": [],
 "humanGraders": [],
 "calls": [{"grader": "G1", "kind": "score", "id": "MECH-01-r1-arm1",
            "sessions": [{"startedUTC": "...", "replies": [{"file": "replies/G1/score/MECH-01-r1-arm1/1-1.txt",
                                                            "receivedUTC": "..."}]}]}]}
```

A call's `kind` is `score` (id: an output), `preference` or `guess` (id: a pair). The record holds every session
and every reply in order. score.py validates each reply with rubric_form.py and gives the call a status:

| Status | Meaning |
| --- | --- |
| completed | the last reply is valid |
| exhausted | 3 sessions, each with a reply and a fix-up reply, all invalid: the grade is missing |
| incomplete | fewer attempts than section 6 prescribes |
| nonconforming | the attempts do not follow section 6 |
| not recorded | a required call that the record does not list |

The registered verdict needs every condition of AMENDMENTS.md A-07: all slots, the registered run order and timing,
every required call completed or exhausted, completion within 21 days, no withdrawn model, and no more than 5 %
ungraded. Otherwise the result says **descriptive results only** and gives what the primary test would have given.
Without `RECORD.json` nothing is scored.

## How the rules are implemented

- **Exact arithmetic.** Every score and mean is a `fractions.Fraction`, so a tie d(q) = 0 stays a tie. (A plain
  float mean of 1, 10/3 and 5/3 is 2.0000000000000004, while that of 0, 1 and 5 is 2.0; a test keeps this case.)
  The JSON output gives each fraction as `{"exact": "p/q", "float": x}`.
- **Per-check merge.** A check is PASS only if every judged grade is PASS. One judgment against CANNOT JUDGE or N/A
  gives the judgment. If neither grade is a judgment, the check is unjudged; if both are N/A, it is N/A. A missing
  grade leaves the other. The mechanism score is 5 × PASS / judged, taken from the merged checks, and it is N/A when
  no check is judged.
- **N/A and ungraded leave the means.** They are listed. They are never scored 0 and never count as a pass.
- **Failed runs.** Mechanism 0, clarity 0, coverage 0, errors E_fail(q) (undefined without a graded output of q),
  defects undefined.
- **The test.** An exact two-sided binomial sign test over the defined d(q) that are not 0. p is an exact fraction;
  a win or a loss needs p < 0.05.
