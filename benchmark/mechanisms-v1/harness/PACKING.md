# Packing and grading driver

Status: **proposed, 2026-11-12; not run-ready**. Implements PROTOCOL sections 6–9
against the scoring harness at `09506df11dff29f28fce51ac06ee57434404f8f5`.
A-14 records the interpretations that still need review. No benchmark generation,
paid service or model call was used to write or test this code.

## Files and boundaries

- `pack.py` checks the full generation table, normalizes both outputs to the same
  pair length, masks text, writes anonymous packets and derives the call orders.
- `native/media.swift` performs Apple Vision OCR and AVFoundation media IO. It is
  a local NDJSON worker. It does not load any model service or use a network.
- `grading_runner.py` writes the exact `RECORD.json` consumed by `score.py`. It
  uses `check_text` and `next_step` after every reply. It ships only the offline
  `RecordedAdapter`. No live grader adapter or credentials are included.
- `tests/test_pack_runner.py` uses original synthetic questions, pixels and reply
  text. Its 20-question integration test executes the real Python packer and
  runner and the unchanged `score.analyse`. Only native media IO and the public
  Git observation are replaced. Other tests exercise individual refusal paths.
- `tests/test_native_media.py` contains three macOS-only acceptance tests. They
  compile the worker and test synthetic video orientation, actual Vision range
  masking, metadata cleanup and native refusals. They skip on Linux.

The native helper **has not been compiled or run on macOS in this change**. The
implementation host is Linux and has neither Apple frameworks nor a Swift
compiler. Native compilation, real synthetic Vision character-box checks,
orientation/color checks, actual MP4 metadata inspection, and the registered
bicycle dry run remain required before run 1. Python tests do not establish
native framework correctness. RUN-LOCK stays DRAFT.

## Input and command line

Build on the designated macOS host, before the dry run:

```sh
swiftc -O benchmark/mechanisms-v1/harness/native/media.swift -o benchmark/media
python3 benchmark/mechanisms-v1/harness/pack.py RUNS.csv SOURCES.json \
  --native benchmark/media --out PRIVATE-STAGING
```

`RUNS.csv` uses exactly the columns and meanings in the harness README. For the primary design, all
question slots, all three runs and both arms must be present, in the registered
chronological order, with non-overlapping times and final `rendered` or `failed`
status. A rendered run past 60 minutes is refused as a harness input error. No
source is required or accepted for a failed slot.

`SOURCES.json` is an object keyed by the rendered output id. Its values are:

```json
{
  "Q00-r1-arm1": {"kind": "video", "path": "originals/story.mp4"},
  "Q00-r1-arm2": {"kind": "captures", "paths": ["originals/frame-000000.png", "originals/frame-000001.png"]}
}
```

This is a schema example with synthetic ids, not a complete design. Paths are
resolved against the process working directory. For Arm 1 select `story.mp4`, or
`loop.mp4` only when no story exists. For Arm 2 list **every original capture in
frame order**. The generation/renderer harness remains responsible for that
source selection, completeness and original run receipts. The packer checks
1280 × 800, the video codec and frame rate, and decode/encode errors. It cannot
prove a supplied capture list is the original renderer output.

The Arm 2 intermediate uses the locked engine's AVFoundation settings: H.264
High, 6,144,000 bit/s at 1280 × 800 × 30, a maximum keyframe interval of 60, and
no frame reordering. Source: locked engine commit `38f3863`,
`Examples/Solid3D/Sources/MartySolidCLI/main.swift`, MovieWriter. Both arms then
use the same normalizer and final writer. The intermediate is kept under
`originals/<output id>/intermediate.mp4`. Original input files remain unchanged;
the generation evidence publisher must retain and publish them separately.

The CLI checks the locked grader-question and rubric hashes. It creates a new
32-byte OS seed **after all outputs have been normalized**. Optional `--seed`
reads an existing private seed for deterministic replay. Do not use replay to
replace a packet set after grading has begun. The packer refuses an existing
output directory and writes its completion manifest last. A failed pack is not
gradable.

For section 2.4, add `--dry-run-questions REVIEWED-DRY-KEY.json`. This input must
be a grader-view document with exactly the registered bicycle question and an
id outside the 20 registered ids. Its facts/checks need review before the dry
run; no such key is invented here. This mode requires one run per arm, marks the
pack `scope: dry-run`, and uses a separate `results/dry-run/` commitment path.
It is excluded from the primary full-design gate. The same media, packet,
retry and timing code applies. The test uses an original synthetic question.

## Output and file hygiene

The operator directory contains:

- `artifacts/<output id>/`: the normalized video, five stills, sheets and transcript;
- `packets/<token>/`: `question.json`, `RUBRIC.md`, and only `output/` or `A/` and
  `B/`, with stills, sheets and transcript. No video, source names or receipts;
- `PRIVATE.json`: the seed, private call identities, orders, packet hashes,
  normalization counts and residual-mask findings;
- `runs.csv`, the two mapping CSV files, and `BLINDING-COMMITMENT.txt`.

**Keep the entire staging directory private.** Publish only the commitment
before grading. The grader adapter gets a new temporary directory containing
only a copy of its packet. Files have fixed permissions and timestamps;
directory timestamps are fixed too. The temporary path is random and has no
arm or token in its name. The seed, mappings, raw replies, order, source paths
and sibling grader records are never supplied to the adapter.

Every frame gets accurate Apple Vision OCR, en-US, correction off. P1, B1 and F1
are matched case-insensitively. Vision supplies the box of each **matched
character range**. The packer pads it by 3 pixels, clips to the frame, and fills
it with the per-channel median of its 1-pixel exterior ring. Overlapping covers
sample the unmodified frame. A full-frame box without a ring is a harness error.
Honest limitation labels are untouched. Stills get a second OCR/mask pass with
6-pixel padding, then another OCR to log remaining matches. There is no manual
edit path. The transcript is OCR of the masked frame every 15 frames, in reading
order, with adjacent equal lines removed.

PNG files are newly encoded RGB with only IHDR, IDAT and IEND chunks. Sheet
thumbnails are 256 × 160, five across and five down, with a fixed bitmap time
font in a 20-pixel caption band. Empty cells remain white. Video is a new silent
H.264 encode with moov first. The MP4 scrubber clears creation/modification times,
handler and compressor names, and optional metadata atoms without changing
sample offsets. It refuses unexpected codecs, extra media handlers and
non-fast-start layout. No source metadata is copied.

Equal seed, input media and pinned Apple framework host give reproducible
packet decisions, tokens and orders. Cross-host or cross-OS byte-identical OCR
or H.264 is **not claimed**; the native tool and host still need RUN-LOCK pins.
Residual rendering style and kept limitation labels can still reveal an arm,
as the registered partial-blinding design states.

## Session and publication gates

A future live adapter must implement `Adapter.open(grader, kind, packet, session_id=...)` and
return a fresh `Session` with `reply(message) -> bytes` and `close()`. The opaque
session id must durably identify that exact conversation. `close()` releases the
local handle without deleting the conversation. `Adapter.resume(grader, kind,
packet, session_id=..., received=...)` must reattach the same session and verify
the durable reply count. It must not send a prompt or create a replacement.
If that cannot be established, it must fail closed. The adapter receives only
its own opaque id and reply count in addition to its packet. Opening
must use the locked model/tool/settings in a fresh isolated session: packet
files only, no web, tools other than reading those files, memory, custom
instructions, other sessions or operator directories. The interface does not
sandbox a hostile adapter. **Only the recorded adapter is shipped**, so a live
adapter requires its own implementation and review before real grading.

The supplied runner CLI replays recorded reply sessions:

```sh
python3 benchmark/mechanisms-v1/harness/grading_runner.py PRIVATE-STAGING \
  --recorded RECORDED-SESSIONS.json --public-branch COMMITMENT-BRANCH
```

It verifies the actual public HTTPS branch with read-only Git, with credential
helpers and inherited Git configuration disabled. It compares the public
commitment with the private seed and refuses a public seed or mapping at the selected
result root (primary or `dry-run`). `PUBLICATION.json` records the observed public commit and observation
time. This is a conservative upper bound on publication time, **not a claimed
Git server push timestamp**. The clock and public repository are trusted inputs.
The observation must follow generation and packing. No user-supplied
`commitmentPushedUTC` or "already pushed" flag can unlock a session. Tests inject
a synthetic publication verifier; the CLI has no bypass flag.

Before any adapter opens, the runner verifies the full design, mapping and
packet hashes, checks publication, then takes the `RUNNER-STARTED` claim and an
OS exclusive lock. A failed publication check leaves no claim. The lock is
released on process exit; a second driver cannot make calls concurrently.
`PUBLICATION.json` is reused on restart, so later observation times cannot
replace the proof that preceded the calls. `RUNNER-STATE.json` binds the pack,
prompts and publication and journals each session and request before adapter IO.
The runner persists `RECORD.json` before a session opens. Each reply's exact
bytes (hex encoded) and original `receivedUTC` are saved in one atomic, fsynced
`replies/.../*.receipt.json` file. Then the exact `.txt` bytes and record are
written and fsynced. The state is written before the scoring record, so recovery
can finish an interrupted record replacement. Saved files are checked against
their receipts. Abandoned temporary files never count as durable replies. Every reply goes through the existing rubric validator and `next_step`:
one parse-error fix-up in the same session, at most two new sessions, acceptance
at the first valid reply, missing only after all six replies are invalid.
The runner sends only the validator's errors as feedback.

A guess has no independent scheduling entry point. It is inserted immediately
after a preference is valid **and durably stored**, in its own new session. An
exhausted preference gets no guess. Every session and reply timestamp must be
nondecreasing; equal instants are permitted by A-13. A backwards clock stops
continuation before another adapter call. Guesses use the same retry state machine.

Adapter/IO failures stop the driver and retain evidence. Rerun the same command
with the **same complete recorded-session file** to resume. The offline adapter
indexes sessions and skips only their durable replies. A prepared session can
open; an opened session can reattach; a reply receipt can be reconciled even if
its `.txt` export or `RECORD.json` was not yet written. `next_step` selects the
same-session fix-up, new session, acceptance or exhaustion from the saved bytes.
No attempt is dropped or repeated. The timestamp floor includes every restored
session and reply, including the preference before a guess. No clock regression
can start or send another call. Completed invocations verify and return the
record without opening any adapter. Completion is persisted before seed release,
so interruption during release is also recoverable.

An interrupted adapter open, or a request intent with **no complete durable
receipt**, is uncertain. The runner stops with an operator-recovery error and
never retries that call. Do not delete the claim, state, record or reply files
to force a restart. Recovery needs an independent adapter audit: retain the
exact session/request identity, bytes and real receipt time. If an exact reply
and time were independently retained, a reviewed operator can restore its
missing `.receipt.json` (`sessionId`, `file`, `receivedUTC`, `rawHex`) for the
pending request; the runner checks its identity and time before reconciliation.
Never invent a receipt time, substitute a new reply, or mark an unknown request
as unstarted. Uncertain opening requires separate adapter-specific review; no
generic bypass or live recovery tool is shipped. Clock failure after a reply
keeps raw bytes for audit but leaves the request uncertain without a valid time.
Legacy records without a journal require review rather than inferred attempts.

After all required calls finish or exhaust their attempts, the runner writes
`BLINDING-SEED.txt` locally. Publication still needs the operator's reviewed
publication step. It never commits or pushes results.
