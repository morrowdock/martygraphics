# Open questions: mechanisms-v1 harness

Status: **OQ-01 to OQ-12 decided, 2026-11-11, before run 1** (by the coordinator, following the independent review at
`58d23865`). The decisions and their labels are in [AMENDMENTS.md](../AMENDMENTS.md). **OQ-13 is still open**; it is a
packer question with no effect on the scoring code. This file records the options that were considered. It changes
no question, key fact, check, prompt, rubric or protocol text.

Each item names what it can change. The four effect classes are kept apart:

- **run score:** the merged mechanism score, errors, coverage, clarity or defects of one run;
- **aggregate:** a mean, rate or count over runs or questions (including M(q, a) and d(q));
- **interval:** a bootstrap interval only;
- **verdict eligibility:** whether the result may carry the registered verdict, not what the verdict is.

| Item | Can change | Decision | Amendment |
| --- | --- | --- | --- |
| OQ-01 applicable core facts | run score (coverage) | A: from the named configuration | A-01, score-affecting |
| OQ-02 E_fail without a graded output | run score (errors), aggregate | B: undefined, left out, counted | A-02, score-affecting |
| OQ-03 the rubric's form | run score (which grade is stored) | strict form with evidence; identity from the mapping; missing only when exhausted | A-03 conformance; A-03b score-affecting |
| OQ-04 N/A under the conventional configuration | run score (mechanism) | C: invalid, retried | A-04, conformance |
| OQ-05 primary bootstrap | interval | the provisional algorithm; NumPy required and pinned | A-05, no score effect |
| OQ-06 agreement bootstrap | interval | section 11 settings; outputs as items; pairs for the preference kappa | A-06, no score effect |
| OQ-07 completed design | verdict eligibility | a dated completion and call record | A-07, no score effect |
| OQ-08 FAIL against NOT SHOWN | nothing | NOT PASS; raw judgments kept | A-08, no score effect |
| OQ-09 HMAC encoding | nothing in the scoring | 32 raw seed bytes, UTF-8 messages, test vectors | A-09, no score effect |
| OQ-10 HASHES.txt wording | nothing | the registration snapshot | A-10, no score effect |
| OQ-11 exploratory analyses | aggregate (coverage), exploratory estimates | coverage = mean of per-run fractions; the rest completed in this pull request | A-11a score-affecting; A-11b no score effect |
| OQ-12 no sign-test sample | nothing (no conclusion either way) | p = 1 with an explicit empty-sample report | A-12, no score effect |
| OQ-13 order permutation | nothing in the scoring | **open** (packer) | — |

## The options that were considered

**OQ-01. Which core facts are applicable in one grader's coverage fraction?**
- A: the facts for the configuration the grader names. **Chosen.**
- B: the core facts minus the grader's `notApplicableFacts`.
- C: the intersection of A and B.

Under A, every covered fact that the fraction ignores gets a warning. Unknown or non-core ids in `coveredFacts` make
the reply invalid (A-03), so they are never silently ignored.

**OQ-02. E_fail(q) when q has no graded output.**
- A: E_fail(q) = 1.
- B: undefined. **Chosen.**

**OQ-03. "Valid JSON in the rubric's form".** The alternatives were:
- a looser form without evidence;
- stopping the analysis on a stored invalid reply.

Chosen: the strict form, including evidence and identity. A grade counts as missing only after the section 6
attempts are recorded (exhausted). The rubric conflicts with itself on the evidence for a CANNOT JUDGE (general rule
5 against its own example and definition); that is resolved in A-03b.

**OQ-04. N/A under the conventional configuration.**
- A: accept it, with a warning.
- B: count it as unjudged.
- C: treat the reply as invalid. **Chosen.**

**OQ-05. Primary bootstrap.** The alternatives were the draw (`rng.choice` or separate calls), the percentile
method, one shared generator, and running without NumPy. Chosen: `rng.integers`, linear percentile, a fresh
generator per analysis, and NumPy pinned.

**OQ-06. Agreement bootstrap.** The alternative was a new stated seed, or checks as items. Chosen: the section 11
settings, with outputs (and pairs) as items.

**OQ-07. Completed design.** The alternative was an operator attestation flag. Chosen: the dated record, verified.

**OQ-08.** The alternative was FAIL ranked stricter than NOT SHOWN. Chosen: NOT PASS (no score effect).

**OQ-09.** The alternative was the 64-character hex string as the key. Chosen: the 32 raw bytes.

**OQ-10.** The alternative was to edit HASHES.txt. Chosen: keep HASHES.txt as the registration snapshot, with a
clarification.

**OQ-11.** The alternatives were a pooled coverage ratio, and leaving analyses for a later pull request. Chosen: the
mean of per-run fractions, and everything completed here.

**OQ-12.** The alternative was p undefined. Chosen: p = 1 with an explicit empty-sample report.

## Still open

**OQ-13. The order permutation of section 8, step 4.** "Each grader's order of calls is a permutation from
HMAC-SHA256(seed, "order:" + grader id)" does not say how a digest becomes a permutation. Two possible
constructions:

- seed `random.Random` with the digest as a big-endian integer, then shuffle the sorted call list;
- sort the calls by HMAC(seed, "order:<grader>:<call id>").

This belongs to the packer and must be fixed, with test vectors, before packing. It cannot change a score: every
call is made, and each call is a fresh session.
