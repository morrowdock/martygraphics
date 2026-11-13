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

### A-15 correction — native G1 no-tool policy (PROPOSED; 2026-11-12)

Baseline: `d6b1cb0ab0a56a4caa2d787c4f3d4e6b3f5b43b4`. Source:
`harness/LIVE-ADAPTERS.md`, native Codex 0.167.2 offline diagnostics and the
upstream `rust-v0.167.2` model/tool implementation cited there.

**VERIFIED offline:** the original feature-only configuration still exposed
eleven tool definitions, including delegation, execution, user-input and sleep.
Its no-tool claim is superseded. The correction uses explicit disable switches
plus a static G1 catalog that removes model-metadata tool overrides. All other
bundled model metadata is retained. Native preflight and regression tests
require the exact allowed tool-definition set `[]` before a model request.
Diagnostic subprocesses have no network or auth. They use the same effective
configuration, environment and filesystem sandbox as the adapter; documented
debug/exec transport-only differences do not select model tools.

No protocol tool exception is requested: packet contents are attached by the
driver. This configuration change can affect model behavior, so its acceptance
is **PENDING**, not an assertion of zero score effect. Fresh homes, durable
transport, exact-session fix-up, uncertain-call refusal and the G2 blocker
remain. No model prompt or quota was used. The protocol, registered keys and
accepted pins are unchanged. RUN-LOCK remains DRAFT.

## A-16 — G2 route changed to Gemini CLI (owner-approved 2026-11-12)

Owner: Collin. Date: 2026-11-12, before run 1. Base:
`7332c125b83c94fd93acfbd1e77645d978e6ce87`. Source: the owner's route decision
and verified official Gemini CLI 0.68.0 help, package documentation and native
offline evidence detailed in [GEMINI-CLI.md](harness/GEMINI-CLI.md).

**Accepted route decision:** replace Antigravity `agy` 1.5.6 with Google's
`@google/gemini-cli` **0.68.0**, using the owner's Google account subscription.
No paid API key or AI-credit overage is allowed. The reason is that agy could
not be shown to meet sections 6 and 9: image input, tool/web denial, and the
fresh-session contract were not established. The historical `LOCK.json` entry
is unchanged. This is a **substantive grader-route change**, recorded before
run 1; it can change grades and verdict eligibility. It is not labelled as
having zero score effect. Scoring arithmetic is unchanged.

**Model finding and proposed run pin (corrected 2026-11-13 UTC):** Argon is
unlisted in Gemini CLI 0.68.0; account access is **PENDING a signed-in check**.
The CLI passes arbitrary `--model` IDs through, so absence from bundled
models is not unavailability. `gemini-3.1-pro-preview` remains strictly a
**PROPOSED fallback requiring owner approval**; its existing adapter pin is
unchanged. No model change is authorized by the CLI route decision. Unknown
IDs do not receive HIGH automatically: a proposed exact-match override for
`gemini-4-argon` explicitly sets `thinkingConfig.thinkingLevel="HIGH"` and is
verified through the native loader without selecting it or sending a request.

**Review correction against `2c17874dfa26cb86f08455c767fb9808f32445af`:** the
initial raw-settings probe missed deep-merged conditional model remaps and
ineffective user `admin.*` disables. Those earlier isolation claims are
**STALE**. Explicit `contexts: []` now removes the remaps; all eight resolver
conditions use the unchanged pin. User and system admin fields are replaced
by schema defaults plus remote settings and are not claimed as disable
controls. Honored controls are `tools.core=[]`, `--extensions none`, empty MCP
configuration, disabled skills/hooks/agents and the isolated filesystem.

**VERIFIED offline implementation evidence:** the probe uses the CLI's real
`loadSettings().merged`, then maps reviewed Config fields. It checks empty
constructed tools and memory, both exact-model HIGH overrides, all access and
customtools conditions, and synthetic text/PNG decoding. Negative probes
reject tool, memory, missing-context and model-policy regressions. Synthetic
process tests cover durable exact-session replies and uncertain no-resend
behavior. A read-only preload checks the final registry and request immediately
before generation, after auth/startup; either generation method refuses tools,
wrong model/thinking, incomplete startup/auth or a second attempt. Its lifecycle
tests are synthetic, with no real auth or model method called.

**PENDING:** genuine post-auth request, remote-admin behavior, signed-in model
access, full multimodal fidelity and real resume acceptance. Built-in
system/environment context remains. `auth-check` stays quota-free; the separate
human-confirmed `model-access-check` sends one minimal request to the pinned
ID and records acceptance/refusal/uncertainty. It was **NOT RUN with the real
CLI** during this correction. Sources: pinned package loader/core and
[GEMINI-CLI.md](harness/GEMINI-CLI.md), checked 2026-11-13 UTC.

No benchmark packet, rubric, real prompt, OAuth flow or model quota was used.
Auth needs the owner's one-time Login with Google. Implementation acceptance,
model acceptance and all other run gates remain open. RUN-LOCK stays DRAFT;
new observations and file pins are under `draftProposals.g2GeminiCli`.

**A-17. Arm 2 and recording shim (2026-11-12; PROPOSED, review pending).**
Source baseline: `9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`, PROTOCOL sections
3–6 and 8 and LOCK.json. New code is in `harness/arm2/` and `harness/shim/`.
The locked generator, CLI, prompts and three.js archive are unchanged.
`RUN-LOCK.json` is unchanged and stays DRAFT. FILES.json records implementation
hashes; it does not promote any draft pin or amend the registered inputs.

The implementation makes one author call and at most three repair calls.
Each HTML reply is rendered, including try four; there is no fifth acceptance
call. `ACCEPT` on call four accepts rendered try three. The exact first question
text and locked prompts are supplied through an isolated, recorded CLI process.
The recorder also installs as Marty's `claude` command without changing Marty.
Only fake CLI processes are used in tests. Real Marty-receipt equality and live
subscription behavior remain dry-run checks, not claims from synthetic tests.

**Interpretations that need review (OQ-15):** if a try has no HTML or cannot
produce a requested still, the repair still has five image blocks. Each missing
image is a white 1280 × 800 placeholder, explicitly labelled in the render
report. It is never a successful capture. The alternative is to stop the run
instead of offering repair. The driver uses integer k below 30 × clamped
duration (rounding the total count up) and floors each still index at the
registered fraction. These choices can affect repairs and images; no claim of
no score effect is made. The author-call maximum remains 900 seconds.

R-WK checks the archive and core-module hashes, serves only the pinned core and
addon JavaScript alongside the authored document, blocks other resources,
awaits readiness and two animation frames per capture, and records console
events. Native synthetic tests check WebGL capture, missing readiness and blocked
network access. The result must be
reviewed before selecting a renderer in RUN-LOCK. R-CR is not implemented or
selected. See `harness/arm2/README.md` for use, evidence and limits.

Legacy tests now generate synthetic keys rather than loading registered question
files. The fixed run-order identifiers are retained, without their question
text or facts. Scoring code, scoring arithmetic and the locked files are not
changed. This work runs no benchmark, no dry run and no model.

The proposed offscreen tool uses the guarded WebKit scheduling selector
`_setWindowOcclusionDetectionEnabled:` and disables App Nap during capture.
WebKitTestRunner uses the same selector at WebKit commit
`fe9858364feb0372faa158caf596ae74c9c9ced0` (checked 2026-11-12). This underscored
API and the host OS/WebKit version need review and pinning. A missing selector
is a harness error. Synthetic capture evidence is not a renderer selection or
permission to run the benchmark.

**2026-11-13 response-policy revision (PROPOSED; review pending).** Based on
`b62f542b7c902e0b209c294f65107d10c6f35872`, R-WK removes HTML head scanning and
serves the unchanged document through its custom scheme with the existing CSP
string in an HTTP response header, including frame/worker restrictions. A
main-frame document-start user script installs the import map before authored
scripts. An isolated blocked-request canary proves policy enforcement, and a
native post-load check refuses missing policy/map before capture. WebRTC
disable/readback, frame counts, timeout and report behavior remain in place.
The README and synthetic validation document the built design and actual host
evidence; no renderer approval, live call or registered run is implied.


**A-18. Registered G2 model conformance and document-start import-map placement
(2026-11-13 UTC; PROPOSED implementation/record correction, review pending).**
Source baseline: `5ff24e627339d99156fda4507da6c783fb878957` (main, merged
[#75](https://github.com/morrowdock/martygraphics/pull/75) on 2026-11-13).
No run 1 or model call is performed by this change. Sources: PROTOCOL sections
3, 5 and 13, LOCK.json's G2 registration, A-16/A-17, and
[harness/G2-REGISTERED-MODEL-VALIDATION.md](harness/G2-REGISTERED-MODEL-VALIDATION.md).

**CONFORMANCE — G2 model identity.** A-16 approved the CLI route, not a model
substitution. Its historical statement that the adapter retains the preview
pin is superseded: both live selections now use registered `gemini-4-argon`
and the exact-id HIGH thinking override. `gemini-3.1-pro-preview` remains only
a named **DISABLED proposed fallback**. The owner-approval amendment flag is
unset; no approval is created here. A future reviewed change must record
explicit owner approval before enabling it. It is never an automatic fallback.
This restores the registered model; it does not assert model equivalence or
account access. Grading with a different model can change scores; no zero-score-
effect claim is made for the erroneous preview selection.

The separate human-confirmed `model-access-check --model` accepts only the
registered ID (default) or that named proposal, refuses the unapproved proposal
before auth/state/process work, and records the tested ID with the existing
one-attempt limit. All access-selection tests are synthetic. Real signed-in
Argon access and full post-auth request acceptance remain **PENDING**.

**Placement interpretation — A-17 response-policy revision.** The already
merged renderer installs the unchanged import-map payload at **document start**,
not at the start of `<head>` as section 5 describes. A main-frame document-start
user script prepends it to the document element without finding/creating a head;
it precedes authored scripts. The unchanged CSP string is an HTTP response
header. This records the implementation difference explicitly rather than
silently treating the placements as identical. Rationale: HTML tokenization
made head scanning unsafe; immutable response policy plus a document-start map
and native post-load checks fail closed. See
[harness/arm2/SYNTHETIC-VALIDATION.md](harness/arm2/SYNTHETIC-VALIDATION.md),
2026-11-13 response-policy revision: first authored static module import resolves
pinned three.js; map removal and omitted configurations refuse with zero frames.
This can affect rendering and repair acceptance; **no score-effect equivalence
is claimed**. Renderer/run approval remains pending. No renderer bytes change
in this PR. PROTOCOL.md is preserved; this dated amendment records the difference
under section 13, without changing questions, prompts, rubric or scoring.

Implementation SHA-256 (old = baseline above; new = this correction):

| File | Old SHA-256 | New SHA-256 |
| --- | --- | --- |
| `harness/gemini_adapter.py` | `991dd9f8b90c15be5d26f1acf400e232c327f7db990c70dac0aff568b45ba0e4` | `7a6b5507abc20c32dd6bf11b24bed8e3493812b4d7f87fb31cea408df480f8f5` |
| `harness/grading_runner.py` | `12b8564d777da499f171881725e383d2f1058632b4c60d32c7c1dcb8bb53d941` | `aad0a4991705292301a22c7f770cc874e2e32e679cc846c390874a9bb8cb0945` |
| `harness/native/gemini_probe.mjs` | `a847f0a954e6f7fe89178ffd150de65afcf9bf612efeccee37764d68f1b3c76b` | `0077e60f7d000842f662498ab6a908baae5c60fb441af45a5c20f65248927945` |
| `harness/tests/test_gemini_adapter.py` | `21cad17ea46a68c695ecfb57cdfd552909bb521ae92075686bbe8dba5d440201` | `1e1ec71c415cdfb87d98ac3ff2fa45603edca95cd02f7ed3766fa96a0dccba6a` |
| `PROTOCOL.md` | `3c59e19e757daeaa68eba030da7d979bfc3d6d1fef409de51864cf1a43b38c9b` | `3c59e19e757daeaa68eba030da7d979bfc3d6d1fef409de51864cf1a43b38c9b` |
| `LOCK.json` | `1a176911a3d339804307f9c080aa6d70b81f0e915ccfb7e61bb0d30017fc3afa` | `1a176911a3d339804307f9c080aa6d70b81f0e915ccfb7e61bb0d30017fc3afa` |

Historical A-17 response-policy renderer transition, already merged in #75:
`harness/arm2/render.swift` at `b62f542b7c902e0b209c294f65107d10c6f35872`
SHA-256 `48ca361b5778acae7629de72e003c6fd98e1299b194e184e0ae91ea120db7be4` -> at the baseline above
`493bcbc157e62925209ffb357892770fa16855fee85bfc70cd94ff3a1f6652ca` (unchanged by A-18).
FILES.json carries current changed-file hashes in existing order; new paths are
appended. RUN-LOCK stays DRAFT. Its historical pins are not reconciled here.


**A-19. Dry packing without registered-key reads (2026-11-13 UTC; PROPOSED
harness narrowing, review pending).** Source baseline:
`9c22a5a50cc37ff7717c68f5be5f7a42af1d0c1f`, A-14, PROTOCOL sections 2.4 and 13,
and [the operator issue](harness/DRY-RUN-RUNBOOK.md).

Dry CLI packing now hashes only RUBRIC.md against LOCK.json and takes all
question/key data from the supplied bicycle grader view. It does not open, hash
or parse either registered question file. Review correction: metadata-only
guards now refuse registered paths, relative paths and symlink/hard-link
aliases through every dry input route, not just the dry key. This includes
sources, runs, seed, lock, rubric, helper/media paths and nested directory
entries. An active Python audit guard rechecks opens and directory walks;
native request paths and returned frame/intermediate paths are checked before
use. Inputs must remain stable and the native helper must be trusted; this is
not a filesystem sandbox. The exact bicycle question and `DRY-BICYCLE` ID are
required. PRIVATE.json gains `registeredQuestionFilesRead` only in dry scope,
computed from the active guard's checked-open path/inode record rather than a
constant. Successful guarded dry packing records false; primary outputs and
integrity checks are unchanged.

The old collision check read registered IDs. Its replacement deliberately
narrows accepted dry IDs to `DRY-BICYCLE`, disjoint from the public fixed set
`MECH-01` through `MECH-20` recorded in the baseline runbook OPERATOR ISSUE and
`harness/tests/support.py::registered_shape_key`. This is non-blinded provenance,
not a fresh validation against registered contents. Dry mode consequently
cannot detect corrupted registered keys or an incompatible future namespace.
The rubric check, full generation-table checks, timing, media normalization,
masking, packets, primary scoring and primary hash/parse path are retained.

**VERIFIED synthetic:** the CLI succeeds with both registered paths guarded by
mode-000, open-denying sentinels under a temporary benchmark root. Negative
tests cover dry IDs/question/private fields, rubric integrity, every input
route and alias form, nested directory entries, native requests and returned
media paths. A late hard-link substitution is refused at the Python open
boundary; the receipt requires an active guard and reflects its inode record.
Primary synthetic output matches the pre-change baseline golden digest over
every output file; primary key/rubric hash refusals remain. No real key was read
and no model call or native dry run was performed. Full operational acceptance
is **PENDING**. RUN-LOCK.json remains unchanged and DRAFT; LOCK.json is unchanged.
FILES.json preserves existing entry order and blinded-file digests, updating
only changed/new files. This amendment does not approve a benchmark run.

Implementation and test SHA-256 (old = baseline
`9c22a5a50cc37ff7717c68f5be5f7a42af1d0c1f`; new = the final file bytes in the
commit containing this review correction):

| File | Old SHA-256 | New SHA-256 |
| --- | --- | --- |
| `harness/pack.py` | `5ec54c199494e3c577f6b796ba3fa55352304f2c8f2887dc258a705bd3abe600` | `9cc0f31567a3f1bca72fdca4bf87e207b6e836c344bc5dbac998b0f4eafb3195` |
| `harness/tests/test_pack_runner.py` | `8ce412c0505e993ee0b2e5a48bd0914a6b34a7a0d84170e58080dabbbcb04303` | `6a52a3d0498a43dd465c5e6ac1c402e0eea934078d89cd3e185dbc280f1e3c4e` |
| `harness/tests/test_pack_cli.py` | NEW FILE (absent at baseline) | `caa20b8dfd6d82ba543c2e9ac2fdd617f742dd6b483351a4a388ae2758d4bc98` |
| `PROTOCOL.md` | `3c59e19e757daeaa68eba030da7d979bfc3d6d1fef409de51864cf1a43b38c9b` | `3c59e19e757daeaa68eba030da7d979bfc3d6d1fef409de51864cf1a43b38c9b` |
| `LOCK.json` | `1a176911a3d339804307f9c080aa6d70b81f0e915ccfb7e61bb0d30017fc3afa` | `1a176911a3d339804307f9c080aa6d70b81f0e915ccfb7e61bb0d30017fc3afa` |

VERIFIED 2026-11-13 UTC: these hashes were calculated only for the explicitly
listed implementation, test and control files. Neither registered question
file was opened or rehashed. The new CLI test file is identified relative to
the baseline, even though it already existed at review head `4e7ab025`.
