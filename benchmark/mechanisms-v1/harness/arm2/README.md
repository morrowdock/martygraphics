<!-- SPDX-License-Identifier: Apache-2.0 -->
# Arm 2 and the recording shim

Status: **PROPOSED, 2026-11-12; review pending. Not a benchmark run.**
Source: PROTOCOL sections 3–6 and 8, LOCK.json and the locked prompts at
`9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`. Isolation flags and the environment
allowlist come from Marty `Sources/MartyLoop/Model.swift` at locked commit
`adbfba98b0665d79e03ac39f89e8be101caa770c`. RUN-LOCK remains DRAFT.

## Boundaries

- `driver.py` accepts one UTF-8 question file at run time. It does not find or
  open registered question files. It preserves the question, including spaces
  and line endings, as the first message's only text block. It checks both
  prompt hashes and uses `claude-opus-5-5` through the recording shim.
- Each author call has a new empty working directory, a separate prompt file,
  no tools, no MCP servers, no slash commands, no settings sources and no
  session persistence. The environment allowlist is the locked Marty list.
  Subscription login variables remain available; no `ANTHROPIC_*` variable is
  passed. Neither this directory nor the benchmark questions are in the cwd.
- The driver makes at most four calls: one author call and three repair calls.
  A repair `ACCEPT` accepts the preceding HTML. An `ACCEPT` on call four thus
  accepts authored try three. Four HTML replies mean four rendered tries and
  **no fifth call**. The locked protocol does not permit asking for acceptance
  after rendered try four. Only the final render determines render success.
- Each repair contains the locked template with fields filled in, then five
  PNG image blocks. All console lines are saved; the prompt gets the first 50.
  Missing HTML has the exact registered error. When captures are unavailable,
  five explicitly reported white placeholders keep the image count fixed.
  This unresolved interpretation is PROPOSED in A-17/OQ-15, not approved.
- The monotonic whole-run budget is 3600 seconds. A renderer receives at most
  300 seconds. An author call receives at most 900 seconds through the same
  recorder function used by the command wrapper; its process group is killed
  on timeout before the streams are closed and the receipt is finalized.
  CLI faults fail closed. The driver never automatically marks a run VOID or
  repeats it; the outer slot coordinator must audit infrastructure evidence.
- A new output directory is mandatory. Exact CLI bytes and parsed reply text,
  every authored page, all captures, console reports, and `run.json` are kept.
  Renderer stdout and stderr are also retained when the subprocess times out,
  before the driver creates its fallback report. HTML fences close only on a
  standalone fence line of the same character and at least the opening length,
  with up to three spaces of indentation; embedded JavaScript backticks do not
  terminate the source. Both backtick and tilde fences are supported, including
  CommonMark's end-of-input termination for an unclosed block.
  The final `source` object can be used as the packer's captures source. The
  packer, not this renderer, performs the registered H.264 intermediate encode,
  masking and partial blinding. Raw captures are not grader packets.

## R-WK

`render.swift` uses an offscreen, borderless AppKit window and a nonpersistent
WKWebView. It requires a 1280 × 800 CSS viewport at `devicePixelRatio === 1`.
It refuses another scale rather than silently resampling. It uses system fonts.
The window fixes its backing scale at one and disables screen-size constraints.
The measured JavaScript viewport is saved in `observedViewport`. Offscreen
scheduling uses WebKit's guarded `_setWindowOcclusionDetectionEnabled:` selector,
also used by WebKitTestRunner (`Tools/WebKitTestRunner/mac/PlatformWebViewMac.mm`
at WebKit commit `fe9858364feb0372faa158caf596ae74c9c9ced0`, checked 2026-11-12).
This is an underscored API: a host without it is refused, not silently changed
to a visible render or another browser. A process activity prevents App Nap.
It waits at most 30 seconds for `benchReady === true`, requires a finite numeric
duration, clamps to 10–60 seconds with a report note, and requires `benchFrame`.
For each integer k below 30 × duration it awaits `benchFrame(k / 30)`, awaits
two animation frames, and snapshots the whole composited view as PNG. Thus a
fractional last frame count rounds up; still indices round down at each of the
five registered fractions. A frame exception, failed snapshot or timeout fails
the render. Uncaught exceptions, rejected promises, warnings and errors are
recorded. The five stills fail the blank test when each has fewer than 0.5 %
non-modal pixels. No manual inspection or quality rerun is part of the driver.
`events.ndjson` is flushed as events arrive. `progress.json` records the frame,
viewport and pending stage. A background watchdog also enforces the render
deadline if the UI queue stops responding; partial files remain for audit.

The renderer reads the npm archive named by LOCK.json and verifies its SHA-256
before loading any page. It also verifies the locked core module hash. It
serves only that module and JavaScript under `examples/jsm/` from the same
archive, through `bench://local/`; addon integrity follows from the archive
hash. No npm installation or unpinned three.js copy is used. The archive is a
local operator input, not a network dependency at render time.

An import map and restrictive CSP are inserted at the start of the head.
The before-head scanner uses only HTML ASCII whitespace (TAB, LF, FF, CR and
SPACE), including the boundary after an HTML/head tag name; NBSP and vertical
tab do not delimit a tag name. HTML attributes retain quote-aware scanning.
DOCTYPE scanning ends at the first `>`, including inside quoted PUBLIC/SYSTEM
identifiers: the HTML tokenizer emits the token on an abrupt identifier end,
not at a later quote-balanced delimiter. It recognizes an explicit head
case-insensitively or inserts an implicit head before the first content token.
Script/style content is never searched for head-like text.

Before parsing authored scripts, a main-frame document-start user script
installs an invariant checker in WebKit's isolated client content world. The
head is not yet parsed at document start, so a renderer-injected synchronous
checkpoint immediately after the CSP/import map invokes that checker before
authored scripts. A per-render UUID marks the injected nodes and checkpoint.
Both nodes must be direct children of the real `document.head`, have the exact
expected type/content and occur exactly once. Failure stops loading and sends
a clear `head invariant` harness error, with no captured frames. The checkpoint
also stops loading if its event is not acknowledged by the isolated checker.
An isolated mutation observer latches subsequent removal/replacement/content
changes as failures; author-world globals cannot spoof the checker. Native code
checks it again after load and will not start readiness polling or capture
without both checks. A missing/swallowed checkpoint is refused by that native
check. Reports record `headInvariantAtStart` and `headInvariantAfterLoad`.
The scanner is not a general HTML parser: malformed-attribute disagreements are
deliberately tested as fail-closed refusals, not accepted as secure renders.
WK content rules block every other URL scheme; navigation policy denies
external pages. CSP denies connections, frames, workers, external fonts and
other resource types. Before creating the view, R-WK disables peer connections
through the guarded WKPreferences `_setPeerConnectionEnabled:` SPI and checks
the `_peerConnectionEnabled` readback. Missing selectors or a true readback
fail closed. This page-wide native preference cannot be restored by page
JavaScript, including newly created iframe realms. As defense in depth, an
all-frame document-start user script installs non-writable, non-configurable
undefined bindings for the RTC constructors (including the webkit alias).
The native preference is essential: CSP/content rules alone do not stop STUN.
The SPI is declared and implemented in WebKit's
`Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h` and `WKPreferences.mm`
at commit `fe9858364feb0372faa158caf596ae74c9c9ced0` (checked 2026-11-12).
JavaScript cannot browse the operator's files. These
controls use WebKit's process sandbox; this is not a VM for hostile exploits
against WebKit itself. Keep the renderer, archive and output directory under
operator control. Retain the binary and OS/WebKit versions for RUN-LOCK review.
R-CR is **not implemented or automatically selected**.

## Recording for both arms

`../shim/record.py` resolves an absolute `claude` path (or searches absolute
PATH entries), probes `--version` with closed stdin, and refuses anything other
than 2.1.322. Installation does not probe or call a model. During a call it
streams binary stdin/stdout/stderr without text decoding. Receipts include the
argv in JSON and lossless filesystem-byte base64, executable hash, version
probe bytes and hashes, exit code, and each stream's exact bytes and SHA-256.
For output streams, a second hash counts bytes actually written to the caller;
`passThrough` requires both output streams to match. A caller that closes its
pipe cannot receive all bytes; the receipt then does not claim equality.
System prompt file bytes are retained separately. Environment values and
subscription credentials are never written to receipts.
The macOS runtime can add `__CF_USER_TEXT_ENCODING` after launch. Tests exclude
that runtime addition from the child-set comparison and separately prove that
the recorder removes a poisoned parent value. It is not in the allowlist.

For Arm 1, install a wrapper into a new directory before invoking locked Marty:

```sh
python3 benchmark/mechanisms-v1/harness/shim/record.py \
  --executable /absolute/path/to/real/claude --record-dir /private/run/arm1/calls \
  --install /private/run/claude-wrapper
```

Put that directory first in Marty's PATH. The wrapper embeds its recorder
configuration, so it still works after Marty removes non-allowlisted variables.
It passes Marty's argv and bytes unchanged. A synthetic test proves this path;
matching these hashes to **real Marty receipts remains a dry-run gate**.
Do not interpret fake-CLI tests as subscription or live CLI validation.

## Synthetic tests on the Mac mini

Builds and tests on the mini must use the shared heavy-job gate. Download the
locked tarball once, before rendering; the renderer checks its hash itself.

To build just the command-line renderer:

```sh
zsh /Users/collincraig/.t3/scratch/mini-heavy-gate.sh arm2-build \
  swiftc -O benchmark/mechanisms-v1/harness/arm2/render.swift -o /private/tmp/mechanisms-rwk
```

After review, `driver.py` takes `--question-file`, `--out` (a new directory),
`--renderer`, `--three-tarball` and optional `--claude` (an absolute executable
or `claude` on PATH). Do not invoke it with a real CLI as part of these tests.

```sh
curl -fL https://registry.npmjs.org/three/-/three-0.170.0.tgz -o /private/tmp/three-0.170.0.tgz
zsh /Users/collincraig/.t3/scratch/mini-heavy-gate.sh arm2-tests \
  env ARM2_THREE_TARBALL=/private/tmp/three-0.170.0.tgz \
  /path/to/numpy-2.5.4-venv/bin/python3 -m unittest discover \
  -s benchmark/mechanisms-v1/harness/tests
zsh /Users/collincraig/.t3/scratch/mini-heavy-gate.sh tools-tests \
  /path/to/numpy-2.5.4-venv/bin/python3 -m unittest discover -s tools/tests
```

Native tests compile the renderer. `ARM2_RWK_BINARY` can name a previously
gated build. `ARM2_TEST_ARTIFACTS` can name a new directory to retain synthetic
captures and reports. Without macOS, swiftc or the archive, the native tests
are explicitly skipped. All author tests use a fake `claude` script on PATH or
its absolute path. No real model is invoked. Legacy scoring tests now construct
synthetic keys too; discovery no longer opens either registered question file.

The native suite checks 300 cube frames, nonblank WebGL pixels, distinct image
payloads at 0 and 1 seconds, a 30-second readiness timeout, a network fetch that
never reaches a local server, console capture, an invalid archive and a missing
duration. The cube contains only its WebGL canvas, so HTML text cannot hide a
blank WebGL result. Native evidence and any failure are reported separately
from fake-driver success. Acceptance results are recorded in the PR and the
[synthetic validation note](SYNTHETIC-VALIDATION.md), not silently promoted into RUN-LOCK.
