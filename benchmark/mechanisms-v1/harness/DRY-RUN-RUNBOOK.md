<!-- SPDX-License-Identifier: Apache-2.0 -->
# Mechanisms-v1 bicycle dry-run operator runbook

Status: **PROPOSED; NOT RUN. Live readiness is NOT VERIFIED.**
Checked against source on 2026-11-13 UTC at main
`7f02488127732aeadf074cee95afa16c00140ffb`. All `file:line` citations below refer
to that commit, relative to `benchmark/mechanisms-v1/` unless prefixed `harness/`.
They are source evidence, not proof that a command ran. Commands below are for
a later authorized operator. No model call, provider network, sign-in or owner
credential read is part of authoring this document.

This tests **DRY-BICYCLE**, once per arm, outside the registered set and every
benchmark statistic. The Mac mini generates both arms, renders with the pinned
engine and R-WK, and normalizes/masks/packs with Apple frameworks. The Linux
laptop grades the transferred private pack through bubblewrap. Keep LOCK.json
unchanged and RUN-LOCK.json DRAFT. Do not merge as part of this procedure.
Sources: `PROTOCOL.md:35-47,93-97`; `harness/PACKING.md:89-95`;
`harness/LIVE-ADAPTERS.md:137-162`; `RUN-LOCK.json:4,29-37`.

## 1. Preconditions and owner gates

1. **OWNER GATE — approve the dry-run scope and review choices.** Record approval
   of this two-host procedure, the reviewed bicycle grader-view key, A-14's
   packing/order/rounding choices, A-15's G1 isolation, A-17's repair placeholders
   and renderer behavior, and A-18's document-start import-map interpretation.
   These can affect evidence; do not call them score-neutral. Use A-16's approved
   Gemini CLI route and A-18's registered Argon selection; historical agy and
   preview-pin instructions are superseded. Approval and host acceptance:
   **NOT VERIFIED**. Sources: `AMENDMENTS.md:172-244,246-309,311-368,370-424,427-467`;
   `harness/GEMINI-CLI.md:79-101`.

2. **OWNER GATE — Google sign-in, on Linux.** The owner launches the pinned
   Gemini CLI, selects **Login with Google**, finishes sign-in and exits without
   entering a prompt. No API-key/Vertex route. An authorized operator may then
   run the local `auth-check`; it reads the OAuth file and is therefore outside
   this document-authoring task. Never print or copy credentials into evidence.
   Current sign-in state: **NOT VERIFIED**. Source: `harness/GEMINI-CLI.md:237-258`.

   ```sh
   ~/.local/share/martygraphics-gemini-cli-0.68.0/node_modules/.bin/gemini
   python3 benchmark/mechanisms-v1/harness/gemini_adapter.py auth-check
   ```

3. **OWNER GATE — one confirmed Argon model-access-check.** After sign-in and
   explicit permission for this separate quota-consuming request, run the
   following once in a new private directory outside Git. Retain its private
   `MODEL-ACCESS-CHECK.json`. Require tested model `gemini-4-argon` and `accepted`;
   refusal or uncertainty means STOP and review, not fallback or another blind
   attempt. The command sends only `Reply OK.`, with at most one generation POST.
   This does not prove multimodal fidelity or exact-session fix-up. Access and
   those live properties: **NOT VERIFIED**. Sources:
   `harness/GEMINI-CLI.md:225-235,260-284`; `AMENDMENTS.md:435-450`.

   ```sh
   python3 benchmark/mechanisms-v1/harness/gemini_adapter.py model-access-check \
     --binary "$HOME/.local/share/martygraphics-gemini-cli-0.68.0/node_modules/.bin/gemini" \
     --work /absolute/new/private/argon-access-check \
     --model gemini-4-argon --confirm-model-request
   ```

4. **OWNER GATE — subscription quota.** Record approval of the planning estimate:
   **4–10 Claude generator calls**, including Marty's planning/repair work and
   Arm 2's author/repair calls; **8 initial grader sessions** if both arms render
   and both preferences validate (per grader: two scores, one preference, one
   separate guess). At most **24 grader sessions / 48 reply attempts** under
   three sessions and two replies per call. Guesses occur only after a valid,
   stored preference; failures can reduce the count. The Argon access-check is
   additional. These are planning bounds for one pair, not measured usage or
   a bound including infrastructure void reruns. Pause for renewed quota review
   before extra infrastructure work or any optional live smoke test (two more
   prompts per grader). Use subscriptions only; no paid API or AI-credit overage.
   Approval, actual calls and remaining quota: **NOT VERIFIED**. Sources:
   `PROTOCOL.md:103-106,117-140,172-198,294-297`;
   `harness/arm2/README.md:21-36`; `harness/PACKING.md:185-194`;
   `harness/GEMINI-CLI.md:62,286-291`.

5. **OWNER GATE — public dry-run commitment.** Agree in advance to publish the
   commitment at `results/dry-run/BLINDING-COMMITMENT.txt`, then approve the exact
   commitment-only diff after packing. This runbook PR is neither that approval
   nor a commitment. No grading before the actual public branch is verified.
   Approval/publication: **NOT VERIFIED**. Sources: `PROTOCOL.md:273-286,313-314`;
   `harness/PACKING.md:89-95,163-171`; `AMENDMENTS.md:213-221`.

6. Prepare a separately reviewed grader-view key named `DRY-BICYCLE-KEY.json`,
   with exactly one id `DRY-BICYCLE` and exactly this question (no extra words):
   `How does a bicycle's chain and sprockets change how hard you pedal?`
   Facts, accepted variants and checks require review; do not invent or borrow
   them from the registered question files. Prepare `DRY-BICYCLE.txt` containing
   just the UTF-8 question, without a trailing newline, for both generators.
   Key readiness: **NOT VERIFIED**. Keep the operator separate from graders;
   do not inspect graded outputs before seed publication. Sources:
   `PROTOCOL.md:95-97,121-127,145-147,467-470`;
   `harness/PACKING.md:89-95`; `harness/arm2/README.md:12-20`.

## 2. Prepare the hosts and record pins

1. Record the reviewed harness commit and clean source state on both hosts.
   Use separate private working directories outside Git, mode 0700, with enough
   space for every attempt, full-resolution capture and original video. Use
   `umask 077`. Do not copy a home/config/session directory between hosts.
   Define absolute paths for `HARNESS_REPO`, `PYTHON` (Python >=3.11 with NumPy
   2.5.4), `PRIVATE_RUN`, and the tool binaries. These names below are operator
   placeholders, not discovered installations. Two-host readiness and free
   space: **NOT VERIFIED**. Sources: `RUN-LOCK.json:8-37`;
   `harness/PACKING.md:99-113`; `harness/GEMINI-CLI.md:132-137`;
   `harness/LIVE-ADAPTERS.md:157-162`.

2. **Mac mini:** record hardware, macOS build, WebKit framework version, Swift
   compiler/SDK, exact Python and NumPy, and SHA-256 of every executable used:
   Claude Code **2.1.322**, Marty built at
   `adbfba98b0665d79e03ac39f89e8be101caa770c`, the check/render engine and
   `marty-solid` built at `38f3863d5ed27c94fccf44b5f117a43938b79455`, R-WK and
   the `media.swift` worker. Record source commits as well as binary hashes;
   latest main is not the Arm 1 engine. Record the three.js **0.170.0** npm
   archive SHA-256 and core module check against LOCK.json. Use the archive,
   not an npm installation. Do not read/hash either registered question file
   while collecting pins. Actual host pins: **NOT VERIFIED**. Sources:
   `PROTOCOL.md:35-47,154-170`; `RUN-LOCK.json:26-37`;
   `harness/arm2/README.md:74-79,124-145`.

3. Run **every heavy build/test/render/packing job on the mini through the shared
   heavy-job gate**. Verify that gate exists and coordinate its use; if unavailable,
   stop rather than bypass it. Build into the private directory, retain compiler
   logs, and record binary hashes. Build Marty and marty-solid with their reviewed
   build instructions at the pinned source commits, also under this gate; their
   build commands are not specified by these harness docs and are **NOT VERIFIED**
   here. The documented harness builds and synthetic checks are:
   Sources: `harness/arm2/README.md:161-200`; `harness/PACKING.md:43-49`;
   `PROTOCOL.md:37-39`.

   ```sh
   cd "$HARNESS_REPO"
   GATE=/Users/collincraig/.t3/scratch/mini-heavy-gate.sh
   zsh "$GATE" dry-rwk-build swiftc -O \
     benchmark/mechanisms-v1/harness/arm2/render.swift -o "$PRIVATE_RUN/mechanisms-rwk"
   zsh "$GATE" dry-media-build swiftc -O \
     benchmark/mechanisms-v1/harness/native/media.swift -o "$PRIVATE_RUN/media"
   zsh "$GATE" dry-harness-tests env ARM2_THREE_TARBALL="$THREE_TARBALL" \
     ARM2_RWK_BINARY="$PRIVATE_RUN/mechanisms-rwk" \
     "$PYTHON" -m unittest discover -s benchmark/mechanisms-v1/harness/tests
   zsh "$GATE" dry-tools-tests "$PYTHON" -m unittest discover -s tools/tests
   shasum -a 256 "$CLAUDE_BIN" "$MARTY_BIN" "$MARTY_SOLID_BIN" \
     "$PRIVATE_RUN/mechanisms-rwk" "$PRIVATE_RUN/media" "$THREE_TARBALL"
   ```

   Retain native acceptance evidence. Require nonblank WebGL frames, 1280×800
   CSS pixels at scale 1, enforced response CSP/document-start map, WebRTC
   disable/readback, and timeout/error behavior. R-CR is not implemented and is
   not an automatic rescue path. Historical Mac synthetic passes are not this
   dry run's acceptance. Sources: `harness/arm2/README.md:49-128,187-200`;
   `AMENDMENTS.md:394-424,452-467`; `harness/PACKING.md:29-39`.

4. **Linux laptop:** record hardware/OS/kernel, bubblewrap version, Python/NumPy,
   native Codex CLI **0.167.2** version and binary SHA-256, Gemini CLI **0.68.0**
   entry-point/package-tree/archive hashes, Node version/hash and runtime binding.
   Compare G2 pins and digest construction with GEMINI-CLI.md; do not substitute
   a wrapper or copy only the Gemini entry point. G1 is `gpt-6.1-sol`, reasoning
   high; G2 is `gemini-4-argon`, thinking HIGH. There is no approved preview
   fallback. Actual host/runtime acceptance: **NOT VERIFIED**. Sources:
   `harness/LIVE-ADAPTERS.md:21-43,157-162`;
   `harness/GEMINI-CLI.md:11-43,79-101`; `RUN-LOCK.json:65-83,119-144`;
   `AMENDMENTS.md:435-450`.

5. On Linux run quota-free adapter checks in new private directories. G1's dry
   plan starts no process; G2's `check` uses network-unshared bubblewrap without
   auth. The real runner additionally requires G1's native empty-tool diagnostic
   and G2's guards. Do not use `--run` as an offline check. Keep real multimodal,
   remote-admin and exact-session acceptance **NOT VERIFIED** until evidence
   establishes them. Sources: `harness/LIVE-ADAPTERS.md:79-115,188-222`;
   `harness/GEMINI-CLI.md:139-192,225-235,286-291`.

   ```sh
   "$PYTHON" benchmark/mechanisms-v1/harness/grading_runner.py self-test \
     --grader G1 --binary "$CODEX_BIN" --work "$G1_DRY_WORK" --dry
   "$PYTHON" benchmark/mechanisms-v1/harness/gemini_adapter.py check \
     --binary "$GEMINI_BIN" --work "$G2_CHECK_WORK"
   ```

## 3. Generate DRY-BICYCLE on the Mac mini

1. After all relevant owner gates, run the two arm slots sequentially in fresh
   directories; no output/quality inspection until both finish. Keep the exact
   question bytes. Install the recording wrapper and put it first on Marty's
   PATH; the wrapper must point at the real pinned Claude binary. Sources:
   `PROTOCOL.md:114-140,187-194`; `harness/arm2/README.md:130-159`.

   ```sh
   "$PYTHON" benchmark/mechanisms-v1/harness/shim/record.py \
     --executable "$CLAUDE_BIN" --record-dir "$PRIVATE_RUN/arm1-calls" \
     --install "$PRIVATE_RUN/claude-wrapper"
   QUESTION="$(cat "$PRIVATE_RUN/DRY-BICYCLE.txt")"
   zsh "$GATE" dry-arm1 env PATH="$PRIVATE_RUN/claude-wrapper:$PATH" \
     "$MARTY_BIN" ask "$QUESTION" --out "$PRIVATE_RUN/arm1" \
     --model claude-opus-5-5 --repairs 3 --no-research --render
   ```

   Verify the accepted document from Marty's receipt, then substitute its exact
   path as `ACCEPTED_DOCUMENT` below. Retain every candidate, engine reason, attached
   fact, call stream/argv/exit code, receipt and original render. Compare recorder
   hashes and `passThrough` to the real Marty receipts; equality is **NOT VERIFIED**
   until checked. The slot's 60-minute budget includes rendering; enforce it in
   the outer coordinator, with 900 seconds per model call. No accepted document,
   Marty/render error, neither video, or timeout is a failure. Source:
   `PROTOCOL.md:117-134`; `harness/arm2/README.md:135-159`.

   ```sh
   zsh "$GATE" dry-arm1-solid "$MARTY_SOLID_BIN" render \
     "$ACCEPTED_DOCUMENT" "$PRIVATE_RUN/arm1/render" \
     --size 1280x800 --story-fps 30 --loop-fps 30
   ```

2. Run Arm 2 using the same question and real Claude executable. Retain every
   candidate HTML, repair still/report, raw stream, console log, capture and
   `run.json`. At most four calls, no fifth acceptance request; an `ACCEPT`
   response keeps the preceding HTML. The driver enforces 900 seconds per call,
   300 seconds per render and 3600 seconds overall. Source:
   `harness/arm2/README.md:12-47,173-175`; `AMENDMENTS.md:377-392`.

   ```sh
   zsh "$GATE" dry-arm2 "$PYTHON" benchmark/mechanisms-v1/harness/arm2/driver.py \
     --question-file "$PRIVATE_RUN/DRY-BICYCLE.txt" --out "$PRIVATE_RUN/arm2" \
     --renderer "$PRIVATE_RUN/mechanisms-rwk" --three-tarball "$THREE_TARBALL" \
     --claude "$CLAUDE_BIN"
   ```

3. Record both final slots in `RUNS.csv`, exactly
   `question,arm,run,status,startedUTC,endedUTC,tries,costUsd`, using
   `DRY-BICYCLE`, arm 1 or 2, run 1, and actual UTC times, tries and subscription
   cost equivalent. Keep non-overlapping generation times and all void logs.
   Only recorded host/network/subscription-limit faults permit `-v2`, `-v3`;
   the third fault fails the slot. No quality reruns. Do not fabricate success
   to obtain a full pair. Sources: `PROTOCOL.md:188-200,376-377`;
   `harness/PACKING.md:51-55`; `harness/README.md:68-75`.

## OPERATOR ISSUE — registered-key reads removed from dry packing

**Historical issue (VERIFIED at baseline
`9c22a5a50cc37ff7717c68f5be5f7a42af1d0c1f`):** pack.py hashed registered
GRADER-QUESTIONS.json and parsed it for IDs even with `--dry-run-questions`.
The former no-read blocker is addressed by the A-19 implementation below;
its review/acceptance is **PENDING**. Checked 2026-11-13 UTC.

**VERIFIED with synthetic CLI tests:** dry mode branches before the
registered-key hash/parse. It still verifies RUBRIC.md against LOCK.json,
loads only the supplied dry grader view, and requires the exact section 2.4
bicycle question and dedicated `DRY-BICYCLE` ID. Registered paths and their
symlink/hard-link aliases are refused as the dry key without opening them.
PRIVATE.json records `scope: dry-run` and `registeredQuestionFilesRead: false`.
All media, timing, masking and packet checks remain. Primary hash refusals and
a byte-for-byte golden output from the baseline remain covered on synthetic
fixtures. Sources: `pack.py::main`, `pack.py::check_dry_run_view`,
`tests/test_pack_cli.py`, and [PACKING.md](PACKING.md).

**Trade-off (PROPOSED, review pending):** exact `DRY-BICYCLE` replaces reading
the registered IDs. The non-blinded fixed-ID record in this runbook's baseline
OPERATOR ISSUE and `tests/support.py::registered_shape_key` lists `MECH-01`
through `MECH-20`, disjoint from `DRY-BICYCLE`. Dry packing does not revalidate
that record against blinded contents and cannot detect registered-key
corruption or a future namespace change. This does not grant access to either
registered question file. See A-19 in [AMENDMENTS.md](../AMENDMENTS.md).

**Before operational use:** land/review this change and satisfy the owner gates
above. Synthetic verification is not real native packing or dry-run acceptance;
those remain **NOT RUN** by this change. RUN-LOCK remains DRAFT.

## 4. Normalize, mask and pack on the Mac mini

1. **Only after the OPERATOR ISSUE change is reviewed and landed**, create `SOURCES.json` keyed by
   `DRY-BICYCLE-r1-arm1` and `DRY-BICYCLE-r1-arm2` for rendered slots only. Arm 1
   uses `{"kind":"video","path":"/absolute/path/to/story.mp4"}` (loop only
   if no story). Arm 2 uses `{"kind":"captures","paths":[...]}` with every
   original capture in frame order from its final `source`. Never list failed
   slots or use repair stills as captures. Retain originals separately. Sources:
   `harness/PACKING.md:51-80`; `harness/arm2/README.md:37-47`.

2. Run the following under the mini gate with a new `MAC_STAGE` outside Git.
   Omit `--seed` for a first pack; let the packer generate 32 random bytes after
   normalization. Do not reuse a failed destination or replace packets once
   grading has begun. Packing success is **NOT VERIFIED**. Sources:
   `harness/PACKING.md:43-49,82-95`; `PROTOCOL.md:273-275`.

   ```sh
   zsh "$GATE" dry-pack "$PYTHON" benchmark/mechanisms-v1/harness/pack.py \
     "$PRIVATE_RUN/RUNS.csv" "$PRIVATE_RUN/SOURCES.json" \
     --native "$PRIVATE_RUN/media" --out "$MAC_STAGE" \
     --dry-run-questions "$PRIVATE_RUN/DRY-BICYCLE-KEY.json"
   ```

3. Check completion (`PRIVATE.json` written last, `scope: dry-run`,
   `registeredQuestionFilesRead: false`), pack inventory
   and normalization reports without hand-editing images. Arm 2 first gets the
   engine-matched H.264 intermediate, retained under `originals/`. Both arms then
   decode at 30 fps, require 1280×800, clamp L to 10–60 seconds and hold to pair T.
   Check five stills at L fractions, 10-fps sheets over T, masked OCR every 0.5 s,
   and silent fast-start video. Require automatic P1/B1/F1 masks and logged
   residual matches; keep honest limitation labels. Primary graders get only
   stills, sheets, TEXT, question and rubric, never video. Sources:
   `PROTOCOL.md:202-229,254-269`; `harness/PACKING.md:74-87,99-137`;
   `AMENDMENTS.md:200-212`.

## 5. Transfer private staging Mac → Linux

This transfer procedure is **PROPOSED; NOT VERIFIED across hosts**. It implements
PACKING's private-directory boundary; transfer itself is not a published
benchmark step. Use an owner-approved private SSH destination on the laptop,
with mode 0700 outside Git, and enough disk space under its private storage
rather than quota-limited `/tmp`. Keep Mac originals. Sources:
`harness/PACKING.md:99-113,133-137`; `harness/GEMINI-CLI.md:132-137`.

1. Freeze the completed Mac pack before any runner starts. Make a SHA-256 manifest
   **outside** the staged directory, using relative paths, rejecting links and
   special files. Transfer only this pack and its manifest to a fresh private
   destination over the approved SSH channel; not the repository, credential
   files, generator homes or adapter homes. The full pack may cross hosts only
   into private operator staging. This includes PRIVATE.json, seed, mappings and
   orders; none may become public or grader-visible yet. Sources:
   `harness/PACKING.md:99-113,173-179`; `harness/LIVE-ADAPTERS.md:129-162`.

   Example manifest creation on Mac (paths are operator-supplied):

   ```sh
   "$PYTHON" - "$MAC_STAGE" "$MAC_MANIFEST" <<'PY'
   import hashlib, json, pathlib, sys
   root = pathlib.Path(sys.argv[1]).resolve()
   manifest = pathlib.Path(sys.argv[2]).resolve()
   assert not manifest.is_relative_to(root)
   rows = []
   for p in sorted(root.rglob('*')):
       if p.is_symlink():
           raise SystemExit('refuse symlink')
       if p.is_dir():
           continue
       if not p.is_file():
           raise SystemExit('refuse special file')
       rows.append([p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()])
   with manifest.open('x') as f:
       json.dump(rows, f, indent=2)
       f.write('\n')
   PY
   # LINUX_PARENT is a fresh 0700 private directory; preserve the stage basename.
   scp -rp "$MAC_STAGE" "$MAC_MANIFEST" "$LINUX_SSH:$LINUX_PARENT/"
   ```

2. On Linux, independently regenerate the same manifest from the received
   `LINUX_STAGE` using the script above with Linux path arguments and a new
   manifest filename. Byte-compare it to the transferred manifest; compare the
   manifest SHA-256 on both hosts over the approved channel. Require identical
   path sets and every hash before continuing. Retain both manifests privately.
   Never regenerate media on Linux or repair mismatches by editing packets;
   stop, preserve evidence and retransmit from the frozen Mac source. The runner
   also checks mapping/packet hashes. Sources: `harness/PACKING.md:133-135,173-185`.

3. Before grading, **only BLINDING-COMMITMENT.txt may leave private staging for
   public Git**. Each isolated grader receives only its own anonymous packet.
   No originals, video, seed, mapping, orders, source names, prior/sibling grades
   or credentials reach it. The coordinator keeps receipts and transfer hashes
   private until the publication review below. Sources:
   `harness/PACKING.md:101-113`; `PROTOCOL.md:273-289,301-314`.

## 6. Publish the commitment, then grade on Linux

1. **OWNER GATE — exact public diff.** Copy the pack's generated commitment,
   unchanged, to `benchmark/mechanisms-v1/results/dry-run/BLINDING-COMMITMENT.txt`
   in a publication branch. Show the owner the exact file/diff and intended
   public repository/branch, record approval, then commit and push only that
   commitment and any required append-only FILES.json entry. Do not stage private
   directories. Record the public SHA; no merge is required. The seed/mapping
   must remain absent from this result root. Publication: **NOT VERIFIED**.
   Sources: `PROTOCOL.md:273-286,313-314`; `harness/PACKING.md:89-95,108-113,163-171`;
   `AMENDMENTS.md:484-485`.

2. With reviewed runtime pins and approved quota, start one driver on Linux.
   `ADAPTER_STATE` must be private, outside every Git repository and outside the
   pack. `CODEX_AUTH_ONLY` names an authorized auth-only file; the runtime can
   copy it, but nobody prints its contents. Gemini uses its owner's local OAuth
   file by default. Neither credential is transferred from the Mac. This is a
   **live command**, not a test to run while editing this document. Sources:
   `harness/LIVE-ADAPTERS.md:137-162`; `harness/GEMINI-CLI.md:103-137,286-291`;
   `harness/PACKING.md:141-154,163-194`;
   CLI flags: `harness/grading_runner.py:1098-1136`.

   ```sh
   "$PYTHON" benchmark/mechanisms-v1/harness/grading_runner.py "$LINUX_STAGE" \
     --live --adapter-state "$ADAPTER_STATE" \
     --codex-bin "$CODEX_BIN" --codex-auth "$CODEX_AUTH_ONLY" \
     --gemini-bin "$GEMINI_BIN" --public-branch "$COMMITMENT_BRANCH"
   ```

   Require the runner's real read-only public HTTPS verification and retained
   `PUBLICATION.json` before calls. Its observation time is a conservative upper
   bound, not a Git server push timestamp. Keep `RUNNER-STARTED`, the OS lock,
   journal, `RECORD.json`, receipts and exact replies. Do not supply an invented
   publication timestamp or bypass failed verification. Source:
   `harness/PACKING.md:163-185`; `AMENDMENTS.md:217-235`.

3. Let the validator control attempts: first valid JSON wins; one parse-error
   correction in the same exact conversation, then at most two new sessions
   (three total). Feedback contains only validator errors. Exhaustion means
   missing, not zero; both missing means ungraded/unjudged and must be listed.
   A guess is a new session only after its preference is valid and durably
   stored; exhausted preference means no guess. Never open sibling results to
   coach a grader. Sources: `PROTOCOL.md:195-200,294-303`;
   `harness/PACKING.md:185-194`; `AMENDMENTS.md:188-199`.

4. Stop on adapter/IO faults, wrong model/session/tool events, uncertain transport
   or backwards clocks. Preserve state; rerun the same command only when its
   durable state allows resume. Never delete state or resend an uncertain call.
   A known completed first reply may receive its fix-up with the saved UUID;
   uncertain open/send needs independent reviewed evidence with original bytes
   and receipt time. No invented timestamps or replacement replies. Live
   recovery acceptance remains **NOT VERIFIED** until demonstrated. Sources:
   `harness/PACKING.md:196-224`; `harness/LIVE-ADAPTERS.md:224-250`;
   `harness/GEMINI-CLI.md:105-112`; `AMENDMENTS.md:222-235`.

## 7. Publish evidence and fill the post-run record

1. After every required call finishes or exhausts, verify the runner's local seed
   release and commitment agreement. Publish the seed and arm mapping through a
   reviewed evidence PR, then inspect graded outputs. Keep this bicycle result
   explicitly **dry-run harness evidence**, excluded from all registered
   statistics and any win/loss verdict. Do not feed it into the primary
   20-question scoring CLI to manufacture a result. Sources:
   `harness/PACKING.md:222-224`; `PROTOCOL.md:93-97,285-286,467-470`;
   `AMENDMENTS.md:213-216`.

2. Assemble the reviewed public evidence within seven days of grading's end:
   every candidate and generator input/output/argv/exit code; every repair and
   render report; all generation receipts, failure/void logs and RUNS.csv;
   original unmasked stills/videos/captures/intermediates; masked artifacts and
   packets; exact grader reply text and its runner receipts/RECORD.json; seed,
   mapping, commitment, public observation, host/tool pins and a dry-run outcome
   report with actual counts, failures and limitations. Include the transfer
   integrity record after privacy review and SHA256SUMS for every published
   item. Large files use release assets with matching hashes. No fictional pass,
   quota use, timestamp or host acceptance. Sources: `PROTOCOL.md:412-427`;
   `harness/PACKING.md:74-80,180-185`; `harness/arm2/README.md:37-47,130-145`.

3. Publish from an explicit evidence allowlist, never a recursive copy of private
   runtime state. **Never publish adapter homes, OAuth/auth files, session
   registries, adapter stderr or raw wire output.** Use the exact grading reply
   exports and reviewed receipts instead. Retain runtime diagnostics privately
   for recovery. For publishable evidence, redact credentials only, using
   `[REDACTED]` and a location list, and run Gitleaks before publication. Explain
   withheld runtime containers without exposing secrets. Sources:
   `harness/GEMINI-CLI.md:132-137`; `harness/LIVE-ADAPTERS.md:157-162,224-250`;
   `PROTOCOL.md:424-427`.

4. In a separate reviewed post-run update, fill
   `RUN-LOCK.json.pendingBeforeRun1.arm2Renderer` with actual R-WK selection,
   source/binary SHA-256, macOS/WebKit version and acceptance-evidence link;
   fill `pendingBeforeRun1.dryRun` with the evidence commit/assets/hashes, outcome,
   recorder equality and live grading/transport observations. Leave a failed or
   untested property **NOT VERIFIED**. Record both hosts' roles explicitly.
   This document PR fills none of those fields and leaves RUN-LOCK DRAFT.
   Sources: `RUN-LOCK.json:4,29-37`; `PROTOCOL.md:44-47,158-161`;
   `harness/arm2/README.md:124-128,155-159`; `AMENDMENTS.md:398-413,464-485`.

5. **Still required before registered run 1:** reviewed harness/scoring commit
   and hashes, accepted amendment/packer/runner choices, generator and
   marty-solid binary pins, exact grader tools/model/settings, host and
   Python/NumPy pins, reviewed native and live acceptance, completed dry-run
   evidence, and all remaining pending fields. Historical draft pins are not
   silently promoted. Only that later review can close run-1 readiness; it cannot
   change LOCK.json or the registered questions/prompts/rubric/scoring. Run 1
   needs its own complete design, seed, commitment and publication gate, separate
   from `results/dry-run/`. Sources: `RUN-LOCK.json:4-37,131-167`;
   `PROTOCOL.md:35-47,183-200,345,394-399,431-439`;
   `AMENDMENTS.md:172-180,237-244,365-368,484-485`.
