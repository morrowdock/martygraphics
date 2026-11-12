# Amendments: mechanisms-v1

Status: **proposed, 2026-11-11, before run 1.** No generation run has started and no output exists, so every decision
below was made without any output or score seen. They take effect when the harness pull request that adds this file
merges. After that, [PROTOCOL.md, section 13](PROTOCOL.md#13-amendments) governs any change.

Each entry has a label:

- **CONFORMANCE.** The harness implements an explicit protocol or rubric rule.
- **SCORE-AFFECTING RESOLUTION OF AN AMBIGUITY.** The protocol text allowed more than one reading; the reading chosen
  can change a run score or an aggregate. It was decided before run 1 without any output seen.
- **NO SCORE EFFECT.** No run score and no aggregate can change. Some of these entries change an interval, a report
  field or verdict eligibility, and each one says which.

**No registration file changes.** These SHA-256 hashes are the same before and after this file:

| File | SHA-256 (old = new) |
| --- | --- |
| PROTOCOL.md | `3c59e19e757daeaa68eba030da7d979bfc3d6d1fef409de51864cf1a43b38c9b` |
| RUBRIC.md | `a64ffa95eac2eb876c2c6a60a3fd4de7fa1f353f5e2ad9b6b7d3ecd70627d305` |
| QUESTIONS.json | `b487e2388187b9580d80ac115072b9912332f9eaa34984519be7396526e308b8` |
| GRADER-QUESTIONS.json | `27be0849c50d02c783eff8cff1d14213ebcb8b8b13d51ec1960cd658f0eef16a` |
| LOCK.json | `1a176911a3d339804307f9c080aa6d70b81f0e915ccfb7e61bb0d30017fc3afa` |
| HASHES.txt | `49f770caf091684e354eee64efffa174c7a4cbe144001ecb00c1b791f33114c3` |

The implementing code is new (it has no old hash). Its hashes are in [RUN-LOCK.json](RUN-LOCK.json) (`harness.scoring`).
The questions these entries answer, with the options that were considered, are in
[harness/OPEN-QUESTIONS.md](harness/OPEN-QUESTIONS.md).

Decided by the coordinator on 2026-11-11, following the independent review of the harness (FIX-FIRST at
`58d23865`).

## CONFORMANCE

**A-03. One rubric-form validator, the section 6 attempts, and reply identity.** Applies OQ-03.
[harness/rubric_form.py](harness/rubric_form.py) is the only definition of "valid JSON in the rubric's form". The
grading runner (`next_step`) and score.py (`call_status`) both use it. It implements:

- RUBRIC.md "Return one JSON object and nothing else": exactly one JSON object, with no fence, no extra text and no
  duplicate key.
- Every key of the answer format.
- General rule 5: for every FAIL, the still or a time in seconds plus evidence. For every error and every defect, a
  still or a time plus one sentence. A `K` error names a key fact of the question.
- The rubric's lists: `configuration` is `conventional`, `unclear` or an accepted variant id. `coveredFacts` holds
  distinct core facts of the question. No fact is both covered and N/A. `clarity` is an integer from 1 to 5.
- Section 8: the reply's question id and its output or pair token must equal the packet's. The token comes from the
  published mapping, and the mapping is checked against the seed.
- Section 6: a call is **completed** when its last reply is valid. It is **exhausted** (the grade is missing) only
  when 3 sessions are recorded, each with a reply and one reply to the parse-error message, all invalid. A call with
  fewer attempts is **incomplete**. A call that breaks the sequence is **nonconforming**. Either of these leaves the
  design incomplete (A-07).

**A-04. N/A under the conventional configuration is invalid.** Applies OQ-04 (option C). RUBRIC.md allows N/A only
when the explainer shows an accepted variant. A check answered N/A with the configuration `conventional` or
`unclear`, or for a question without variants, makes the reply invalid. That starts the section 6 retry, and the
answer never leaves the denominator.

## SCORE-AFFECTING RESOLUTION OF AN AMBIGUITY (decided before run 1, without any output seen)

**A-01. Applicable core facts come from the grader's named configuration.** Resolves OQ-01 (option A). One grader's
coverage denominator is the core facts whose `appliesTo` holds `all` or the configuration that grader names;
`unclear` counts as conventional. The grader's `notApplicableFacts` list is compared with that set, and a
difference is reported as a warning. Every covered fact that the fraction ignores is reported as a warning too. The
other reading (core facts minus the grader's own N/A list) would let a grader set the denominator.

**A-02. E_fail(q) is undefined when q has no graded output.** Resolves OQ-02 (option B). Section 11 defines E_fail(q)
as 1 + the largest merged error count of any graded output of q. When q has no graded output in either arm, that
largest count does not exist. The failed runs of q then have no error value. They leave the error means, and the
report counts them (`efailContributions`, `failedWithUndefinedEfail`). This affects only the exploratory error
analyses. The mechanism score of a failed run stays 0.

**A-03b. A CANNOT JUDGE needs a reason, not a time.** This resolves a conflict inside RUBRIC.md. General rule 5 asks
for "the still or the frame time (seconds) and one sentence of evidence" for every CANNOT JUDGE. But the rubric's
own answer example gives its CANNOT JUDGE the reason "only the gear teeth move; no single feature to follow", with
no time, and the CANNOT JUDGE definition says "Give the reason". The validator therefore requires a non-empty reason
for a CANNOT JUDGE, and a still or a time for a FAIL. The rubric's example reply is valid under this reading (a test
parses it from RUBRIC.md). This can change which replies need a retry, and so which grade is stored.

**A-11a. The coverage aggregate is the mean of per-run fractions.** Applies to section 11, exploratory analysis 6.
It is not a pooled ratio of all covered facts over all applicable facts. A failed run counts as 0, and an output
with coverage N/A leaves the mean.

## NO SCORE EFFECT

**A-05. The primary interval, and NumPy.** Applies OQ-05. The draw is `rng.integers(0, n, size=(10000, n))` with
`np.random.default_rng(20261111)`, the mean of each resample, and `np.percentile(means, [2.5, 97.5])` (linear). The
population is the defined d(q), zeros included. Each analysis gets a fresh generator. NumPy is required at the
version that RUN-LOCK.json pins (`harness.numpy`). Without it, or at another version, the report is refused, so the
primary interval is never silently missing. *Effect:* intervals only.

**A-06. The agreement intervals.** Applies OQ-06. Section 11 settings: 10 000 resamples and a fresh
`default_rng(20261111)` for each statistic. For the score agreement, the items are the outputs that both graders
graded; for the preference kappa, the items are the pairs. A resample in which a statistic has a zero denominator is
left out and counted (`undefinedResamples`). The same rule applies to every ratio interval. *Effect:* intervals only.

**A-07. A dated completion and call record.** Applies OQ-07. The registered verdict needs `RECORD.json`. The code
checks:

- **Run timing (from `runs.csv`):**
  - every slot is present;
  - the runs start in the registered order (`random.Random(20261111).shuffle` of the sorted slots), one at a time;
  - no rendered run is longer than 60 min.
- **Grading timing:**
  - the commitment is pushed after generation ends;
  - every grading session starts after the commitment;
  - each guess comes after its stored preference.
- **Calls:** every required call is completed or exhausted. The required calls are a score call per grader and
  rendered output, a preference call per grader and pair with two rendered outputs, and a guess call after each
  stored preference.
- **Deadline:** generation and grading are complete within 21 days after run 1.
- **Withdrawal:** `withdrawnModels` is empty.
- **Ungraded share:** no more than 5 % of the rendered outputs are ungraded (exactly 5 % still allows the verdict).

Without the record, nothing is scored. With a record that fails any check, the result is "descriptive results
only". *Effect:* verdict eligibility only.

**A-08. A judged non-PASS merge is NOT PASS.** Applies OQ-08. FAIL and NOT SHOWN are not ordered. Both raw judgments
are kept per grader in the result. *Effect:* none (only PASS against not PASS enters a score).

**A-09. HMAC encoding.** Applies OQ-09. Each HMAC uses the 32 raw seed bytes as the key and UTF-8 messages.
`BLINDING-SEED.txt` holds the seed as 64 lowercase hex characters. The commitment is the SHA-256 of that hex string
as ASCII. There are OpenSSL test vectors in
[harness/tests/test_blinding.py](harness/tests/test_blinding.py). *Effect:* none on scores. It fixes the tokens and
sides before any is made.

**A-10. HASHES.txt is the registration snapshot.** Applies OQ-10. In README.md and HASHES.txt, "every other file in
this folder" means the files that were registered when the registration pull request merged. `harness/`,
`RUN-LOCK.json` and this file are pinned in RUN-LOCK.json instead. *Effect:* none. This is a clarification of
wording.

**A-11b. The rest of the exploratory analyses (section 11).** Applies OQ-11. These are now computed, each with the
question-level bootstrap:

- errors on rendered pairs only (the runs whose pair has two rendered outputs; an ungraded output still leaves);
- the question-level preference winner by pair wins: +1, 0 or −1 for each question with a judged pair, averaged.
  This is graded only and with automatic preferences;
- question-level defect means (major and minor);
- success per question and per arm;
- route cost (tries, wall time, and the mean and sum of `total_cost_usd`);
- the per-category table;
- the blinding results. A guess is correct when it names the side that Arm 1 was shown on (the dedicated 3D
  engine). Each grader gets an exact two-sided binomial test of correct against wrong, which is undefined when there
  are no such guesses.

The optional second generator and human graders are reported as "not enabled". If either is enabled, the report is
refused until their separate analysis exists. *Effect:* exploratory estimates and intervals only; never the verdict.

**A-12. No sign-test sample.** Applies OQ-12. When every defined d(q) is 0, or no d(q) is defined, p = 1. The report
then says which one it is (`emptySample`). *Effect:* none (this is no conclusion either way).

**A-13. Re-check fixes before run 1 (2026-11-12).** An independent re-check of the harness found three defects. All are
fixed before run 1, so they are not deviations:

- *Guess timing.* score.py compared the guess's accepted reply with the stored preference. A guess session that
  started before the preference was stored, with a later reply, still allowed the registered verdict. Now every
  guess session, also an exhausted one, must start no earlier than the moment the preference was stored (a start
  at that same instant is allowed); otherwise the timing check
  fails and the result is descriptive only.
- *Malformed fact ids.* rubric_form.py raised `TypeError` for unhashable entries in `coveredFacts`,
  `notApplicableFacts` or an error's `keyFact`, so the retry workflow never saw the reply. These are now validation
  problems, which `next_step` handles as any other invalid reply.
- *Evidence.* A FAIL with only a still or a time (for example `"6.0 s"`) was accepted. RUBRIC.md rule 5 asks for
  the place **and** one sentence of evidence. A program cannot decide in every language whether a text is a good
  sentence (`Chocan.` and `يصطدمان.` are one-word sentences), so this is the machine rule: after the still and time
  references (with an optional `t=`) and file references (`still-3.png`, `frames/x.jpg`, quoted paths) are removed,
  at least **one word** must remain. A word is a run of Unicode letters and combining marks, in any script. Emoji,
  numbers and punctuation alone are refused. Whether the evidence is a good sentence (for example `"6.0 s bad"` is
  accepted by the validator) is left to the grader instructions and the audit; it is not a validity test.

*Effect:* stricter validation and timing only; scoring arithmetic is unchanged. The scoring hashes below are updated.

**A-14. Packer and grading driver (2026-11-12; PROPOSED, review pending).** New
code: `harness/pack.py`, `harness/grading_runner.py`,
`harness/native/media.swift`, and synthetic tests in
`harness/tests/test_pack_runner.py` and `harness/tests/test_native_media.py`.
These files have no old hash. Their proposed
new hashes, and the updated documentation hashes, are recorded only in
`RUN-LOCK.json.draftProposals.packerRunner`; no existing scoring pin or registered
input is changed. The previous AMENDMENTS.md hash remains in `harness.amendments`
until the coordinator accepts the proposal. It is not silently promoted.

*Decided rules reused:* A-03's validator and section 6 attempts, A-09's seed and
HMAC encoding, and A-13's guess-session timing. No scoring, rubric or analysis
rule is changed. The driver stores exact replies in the existing record format.
Native media uses Apple Vision and AVFoundation with the locked MovieWriter
settings, not an alternate OCR implementation or encoder.

*Proposed implementation choices (not yet decided):*

- **OQ-13:** sort primary calls lexicographically by `(kind, anonymous token)`,
  with kind `preference` or `score`. Seed Python `random.Random` with the
  big-endian integer of HMAC-SHA256(seed, `order:` + grader id), then shuffle once.
  A valid, stored preference inserts its separate guess call immediately after
  it. Guesses are conditional follow-ups, not independently permuted primary
  calls; this construction enforces A-13. Each grader has its own permutation.
  Fixed vector: raw seed `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`,
  `order:G1` digest `9d5446cd87fc9d514cc822e34c1d179ed399cda2e7aff600b138ec8575e15acb`.
  For each kind paired with tokens `0`, `1`, `2`, the order is score/1,
  preference/1, preference/2, preference/0, score/2, score/0.
- Source duration is the count of decoded 30 fps frames. L is clamped to 300–1800
  frames. T is the larger L of rendered partners; the last frame is held. Still
  indices are `floor(Lframes * fraction)` at fractions 0.1, 0.3, 0.5, 0.7, 0.9.
  Frame-strip indices are 0, 3, 6, … below T. Text sampling uses 0, 15, 30, … below
  T. These rounding and endpoint choices need review; the evidence rates do not
  change.
- Mask box edges round outwards before padding. The ring is outside the padded,
  frame-clipped box. The median is per channel; a half-integer median rounds
  down. All overlapping masks sample the original pixels and are applied in
  sorted box/color order. F1 treats a token as whitespace-delimited, ending
  exactly in `.json` or `.html`; punctuation after the suffix is not part of
  this rule. Missing Vision range boxes stop packing, rather than hiding the
  entire line. Remaining still matches are logged outside packets.
- The section 2.4 dry-run path has one pair and an explicit `dry-run` scope. It
  needs a separately reviewed bicycle grader-view key, and uses its own public
  commitment under `results/dry-run/`. It cannot satisfy the primary completed
  design. No dry run has been performed.
- The public-branch observation time is used as a conservative publication-time
  upper bound in `commitmentPushedUTC`. The driver fetches and checks the actual
  public commitment before opening any session. It does not assert that Git
  supplied a server push timestamp. The claim is created only after verification
  succeeds. Failed verification permits retry without an attempt.
- **P2 recovery correction (2026-11-12; proposed, review pending):** the driver
  journals session preparation, opening, request intent, exact reply bytes and
  receipt time. It resumes known attempts through `rubric_form.next_step`,
  reattaches the same session for a fix-up, and reconciles durable receipts into
  `RECORD.json` without changing their `receivedUTC`. Publication, prompt and
  pack bindings, the prior timestamp floor, and A-13's preference-before-guess
  gate survive restart. Completed runs are idempotent. An interrupted open or
  request with no durable reply is uncertain and needs operator evidence; it
  is never resent automatically. An OS lock prevents concurrent drivers. This
  corrects the restart refusal in PR #72 head
  `34463c556accac9b6bdd39697567cd7732f1f062`; scoring arithmetic is unchanged.
  New synthetic interruption coverage is in `harness/tests/test_runner_recovery.py`.
  Equality with an uninterrupted record is tested with matching event times;
  real downtime can advance later timestamps, never the stored receipt time.

*Effect and limits:* the order and record plumbing do not change registered
scoring arithmetic. OCR, masking, image sampling and session ordering can affect
what a grader sees, so these implementation choices must be reviewed before
run 1; they are not labelled as proven to have no score effect. The Python
pipeline is tested with original synthetic data. Apple-framework compilation
and native synthetic media checks are **pending** on macOS, followed by the
registered dry run. Only a fake/recorded model adapter is shipped. Live grader
adapters, their isolation and tool pins remain pending. RUN-LOCK stays DRAFT.

## A-15 — Live CLI adapter proposal (PROPOSED; not accepted)

Date: 2026-11-12. Base: `9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`.
Sources: LOCK.json grader pins, PROTOCOL sections 6 and 9, the merged runner's
`Adapter.open/resume` contract, local help/version output, and
`harness/LIVE-ADAPTERS.md`. Review and coordinator acceptance are pending.

G1 has a proposed Codex subprocess adapter with explicit packet text and image
attachments, a fresh private home, no inherited environment or host config,
disabled agent web/execution tools, and bubblewrap filesystem isolation.
Only that session's home is retained for its one parse-error fix-up. Exact
reply bytes, wire output, UTC times, tool version, binary hash, session id
and request intent are durable. Timeout, process failure, unknown transport
events, changed session storage and missing completion are uncertain. They
never authorize a replacement request. Interrupted runner receipt creation
still needs reviewed recovery with independently retained evidence.

G2 provides only a fail-closed adapter and a help-confirmed invocation plan.
Antigravity 1.5.6 does not document enough controls in its help to establish
the required isolation or attachment/result contract. It is UNVERIFIED. No
unsupported flags, invented wire schema or alternate provider are presented
as a working implementation. `--live` stops before reading the pack while
this gate is open. See OQ-14 for the exact remaining work.

Local CLI observations: Codex `codex-cli 0.167.2`; Antigravity and its `agy`
alias `1.5.6`. Only help/version commands ran against those CLIs. The Codex
version query also succeeded inside the proposed filesystem sandbox. No
benchmark or synthetic prompt was sent to a real model. The optional
self-test defaults to dry mode and requires explicit `--run` to spend quota.
An `OK` reply alone cannot prove a model has no hidden capabilities.

Existing test dependencies on the registered keys are replaced with original
synthetic metadata. Public numbered ids and registered-order vectors remain.
The production validator, arithmetic, prompts, rubric, protocol, LOCK.json,
and registered question/key files are unchanged. Question/key bytes were not
opened or copied in this work. FILES.json retains their prior digest entries.

Effect: evidence transport and isolation can affect grades; no claim of zero
score effect is made. Arithmetic is unchanged. New hashes are proposed only
under `RUN-LOCK.json.draftProposals.liveAdapters`; existing accepted/draft
historical pins are not silently replaced. RUN-LOCK remains DRAFT.
