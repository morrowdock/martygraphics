<!-- SPDX-License-Identifier: Apache-2.0 -->
# Synthetic validation: Arm 2 and recording shim

Status: **VERIFIED synthetic checks only. Renderer selection and A-17 remain
PROPOSED. No benchmark or section 2.4 dry run was performed.**

The earlier sections are historical evidence at their stated baselines. Their
HTML-scanner design/security claims are **STALE**, superseded by the
2026-11-13 response-policy revision at the end of this document. The third
independent re-check found that the scanner could allow an authored script to
execute before configuration despite a later successful checkpoint.

Checked: 2026-11-12T21:38:47Z, on the Mac mini, arm64.
Protocol baseline: `9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`.
Sources: this directory's renderer and driver, `../shim/record.py`, the synthetic
tests, and their actual local stdout and render reports. Source SHA-256 values:

- `render.swift`: `4094e26ec1c859d5d330c923c83499b838c04dc58be1324edd531ef829eaabbd`
- `driver.py`: `c61a27265b057ed341e74752dd8b48c90dec4b832faac9c7e9361d04efacf056`
- `../shim/record.py`: `2a068629e0001c3cc2348c5ada9e20a34ccc10bcd12dd2152dd0b82b719468c2`

## Verified tests

All builds and test runs used the Mac mini heavy-job gate. The final commands
inside the gate were:

```sh
python3 -m unittest discover -s benchmark/mechanisms-v1/harness/tests
python3 -m unittest discover -s tools/tests
```

The Python environment has the pinned NumPy 2.5.4. The native tests compiled
`render.swift` with `swiftc -O` and used the locked local three.js archive.

- Harness: **190 tests passed**, no skips, in 135.266 seconds. This includes
  all 24 new shim, driver and native renderer tests.
- Tools: **52 tests run; 51 passed, 1 skipped**, in 1.780 seconds. The existing
  setup test reports `setup.sh tools not installed`; no tools code was changed.
- The existing recovery test emitted a Python `fork()` deprecation warning.
  It did not fail. No warning was hidden or converted to a pass.
- Harness log SHA-256: `a4b31909c0d6c6ecd63faee623208fd4f32f3e4e81ad23a3675fad5b86134f19`.
- Tools log SHA-256: `f3b00032f090c2c3766d2bd3e6cd5cff1dd207bdd9f88d00bc6000df13065903`.

## Verified R-WK capture

Host: macOS 27.2, build 26B123. WebKit: `22625.2.8.11.9`.
Renderer executable SHA-256:
`788111e18f3e0f1c5500a9df0699b6f47e4ffc5c11cd6680550415b0b982d491`.
The observed JavaScript viewport was **1280 × 800, scale 1**.

The synthetic cube completed **300 PNG frames**, k = 0 through 299, in
10.514848500024527 seconds, with no harness error or uncaught exception. The
fixture contains only a WebGL canvas; no HTML text can conceal a blank canvas.
The decoded image payloads of frames 0 and 30 differ. Their PNG SHA-256 values:

- Frame 0: `3dee6d697f02a8ba7b1315459466b6bd0e0d0b4fba329d6e03899894dbbc55c6`.
- Frame 30: `c3366b6a6c6399b42f8d0cab2257a1410d886a2e764c116858260fc1e3d6ba16`.

The five stills' non-modal pixel fractions were
`[0.1938193359375, 0.17174121093750006, 0.1938193359375,
0.17174121093750006, 0.1938193359375]`. Each exceeds the registered 0.005 blank
threshold. The warning `synthetic cube ready` was retained.

The network fixture completed 300 frames. Its fetch was blocked by `connect-src`,
and the listening local HTTP server received **zero requests**. The never-ready
page returned the 30-second readiness error; total process/report time was
30.29211908322759 seconds. Its console error was retained. The frame-exception,
missing-duration and bad-archive cases were refused as expected.

## Limits and pending review

Initial synthetic validation found a viewport mismatch and suspended offscreen
animation. The final tool fixes window scale/size, uses the guarded WebKit
offscreen scheduling selector described in README.md, and prevents App Nap.
It does not replace animation frames with timers or change the locked prompts.

R-WK WebGL capture **works on this tested host**. R-CR was not used. This does
not select R-WK in RUN-LOCK, prove another OS/WebKit version, or prove live
Claude subscription behavior. All author calls used fake executables. Real
Marty-receipt matching and the registered dry run remain pending. Registered
question files were not read; the suite now guards against those reads.
LOCK.json, registered prompts, HASHES.txt and RUN-LOCK.json are unchanged.

## PR 75 review fixes: 2026-11-13 UTC

Status: **VERIFIED synthetic regression checks; independent re-review pending.**
Checked: 2026-11-13T00:20:35Z (2026-11-12 on the Mac mini's local clock).
Source baseline: `677849b245bea1898ed4cf0637cb11cc5ca71ee1`, plus the review
fixes identified by these tested source SHA-256 values:

- `render.swift`: `15bc155865688b18a269af38d5c1bef6e03b72e7e58027d9d559ae75a447168b`
- `driver.py`: `4ecf799c7ba7e193a1a544ebc062729c283ebfb09d0d83b265eef28df9099d9a`

The earlier receipt above remains historical evidence for its listed hashes;
these checks cover the revised sources. Every build and test command ran inside
`zsh /Users/collincraig/.t3/scratch/mini-heavy-gate.sh`, waiting for its slot.
The Python venv used NumPy 2.5.4. Both native runs compiled the Swift renderer
with `swiftc -O` inside the gated test process, using the locked local archive.

- Focused driver/shim/native suite: **34 passed**, no skips, 125.811 seconds.
  The full suite below also covers the final CR-only/Unicode fence edge cases.
- Full harness discovery: **200 passed**, no skips, 218.930 seconds.
- Tools discovery: **52 run, 51 passed, 1 skipped**, 1.909 seconds.
  The skip remains `setup.sh tools not installed`.
- The existing recovery test still emits its multi-threaded `fork()`
  DeprecationWarning; it passes, and the warning remains in the log.
- Full harness log SHA-256: `000c0fa211d451dff0731998205901ff10f1dc63cd8c9d29cd56a1118826ab71`.
- Tools log SHA-256: `435859dc06bc8bf60fd398e97710598a80de8b1777e8c9d45ff413daa8522952`.
- Full-suite renderer executable SHA-256: `a746ef27abaac92612be03d6247b554642a187ebcb955ab5b84ac4d075875d3e`.
- Host: macOS 27.2 build 26B123, WebKit `22625.2.8.11.9`.

Review findings and proving tests:

1. **P1 offline WebRTC:** the native peer-connection preference is disabled
   before view creation, with guarded selectors and a false readback required.
   All-frame document-start scripts lock RTC bindings; CSP still denies frames.
   `test_webrtc_main_and_iframe_send_no_udp` completes 300 frames with **zero
   localhost UDP datagrams**. It attempts both peer-connection names in the
   main window, a fresh iframe realm and an iframe with srcdoc, checks that
   page JavaScript cannot restore the main bindings, and observes the
   `about:blank` and `about:srcdoc` navigation refusals. Srcdoc script execution
   is blocked, not counted as an executed frame script.
   `test_network_probes_blocked_without_request_reaching_server` also completes
   300 frames, logs blocked fetch/XHR/WebSocket/image/dynamic-import probes,
   and observes **zero HTTP requests**. The full WebGL cube test still passes.
2. **P2 timeout evidence:** `test_renderer_timeout_preserves_streams_before_fallback`
   launches a synthetic renderer that prints binary stdout/stderr then sleeps
   past a 0.5-second timeout. Exact partial streams survive beside the fallback
   report. `test_renderer_timeout_optional_and_text_streams` covers None and str.
3. **P2 head insertion:** the before-head scanner recognizes actual markup or
   creates the implicit head before content; it never searches script/style
   text for head substrings. `test_comment_before_head`,
   `test_head_in_script_string`, `test_head_in_style_text`, `test_missing_head`
   and `test_uppercase_head_with_attributes` each complete 300 frames with the
   pinned import resolved, CSP present in the head, and nonblank captures.
4. **P2 fenced HTML:** `test_backticks_in_javascript_do_not_truncate_html`
   proves the exact authored source reaches rendering. `test_commonmark_closing_fences`
   covers same/longer backtick and tilde runs, indentation, trailing whitespace,
   nonclosing embedded/short/mismatched fences, LF/CRLF/CR, Unicode separators,
   unclosed blocks and fences nested inside other code blocks.

NOT RUN: live Claude/Marty calls, paid APIs, registered benchmark questions or
the section 2.4 dry run, alternate OS/WebKit compatibility, full engine Swift
package/Xcode builds, and the whole-tree `validate_local.py --check-files`.
That checker opens every tracked file, including forbidden question inputs;
instead, manifest updates use its SHA-256 algorithm on only the explicit changed
paths, preserving all other entries and their order. RUN-LOCK remains DRAFT;
the locked inputs and prompts are untouched. No renderer-selection approval
or real benchmark acceptance is implied.

## PR 75 CSP/head-invariant re-check: 2026-11-13 UTC

Status: **VERIFIED synthetic checks; independent re-review PENDING.
Not a benchmark run.** Checked: 2026-11-13T02:37:09Z on the Mac mini.
Source baseline: `add494d86153bd6ff026f3e4a048bc17b97ba3d4`, plus the changes
identified by these tested source SHA-256 values:

- `render.swift`: `48ca361b5778acae7629de72e003c6fd98e1299b194e184e0ae91ea120db7be4`
- `../tests/test_arm2_renderer.py`: `4aa5024022980b2c3daf8fb3617b0f41c18d96221dedd85aeffe47002e7c6114`
- Renderer executable: `79d67f4ceaef777a30aede6eede62aea72aa9401df888f6359c33e606af83fa6`

The scanner now uses only HTML ASCII whitespace at tag-name boundaries.
DOCTYPEs terminate at the first `>`, including an abrupt end inside quoted
PUBLIC/SYSTEM identifiers, rather than quote-balancing past that delimiter.
A main-frame document-start user script installs an isolated-world invariant
checker; a nonce-marked synchronous checkpoint after the injected policy/map
calls it before authored scripts. It verifies unique, exact nodes directly
under the real head. An isolated mutation observer latches changes, and the
native post-load check must pass before readiness polling or capture.

The initial seven-method focused run passed the malformed-head/DOCTYPE and
network cases but failed two refusal assertions: one proposed malformed-comment
fixture actually parsed safely, and stopping loading before posting the error
let a generic navigation-cancel error win. The refusal fixture now uses a
malformed unquoted HTML attribute that genuinely misplaces the injection, and
the checker posts its specific error before stopping loading. No failure was
silently counted as a pass.

The final focused refusal/baseline run passed **3 test methods**, including
10 baseline head subcases, in **107.337 seconds**. Both refusal cases returned
exit 1, `complete: false`, **0 frames**, and
`head invariant: CSP/import map must be unchanged direct children of document.head`.
The misplaced-injection case also proves the following authored script did
not execute. The policy-removal case proves that a page-world replacement for
the verification function cannot spoof the isolated checker.
Focused log SHA-256: `3abaf99b52c25b0c6cd62b4fa05ac3d050853739b325ffe911a3ac9de43a3979`.

All builds and renderer runs use the shared mini heavy-job gate, including
waiting behind app builds/UI tests. The Python interpreter is 3.14.10 with
NumPy 2.5.4. The final suite reused the gated renderer executable pinned above.
Host: macOS 27.2 build 26B123; WebKit `22625.2.8.11.9`.

- Full harness discovery: **206 passed**, no skips, **390.386 seconds**.
  This is the single final full-harness run after the focused fixes.
- Tools discovery: **52 run, 51 passed, 1 skipped**, **2.187 seconds**.
  The existing skip is `setup.sh tools not installed`.
- All **21 head cases** completed **300 frames** with both invariant report
  fields true, strict direct-child CSP/map probes and resolved pinned imports.
  These comprise the five previously committed cases, ten additional baseline
  cases (a 15-case baseline matrix), NBSP, VT and four quoted PUBLIC/SYSTEM
  cases covering both quote styles. The specific reported PUBLIC example is
  included.
- Both refusal regressions again returned **0 frames** and the specific head
  invariant error. The misplaced-injection case did not run authored code.
- WebRTC and network probes each completed **300 frames**. Local listeners
  recorded **0 UDP datagrams, 0 accepted TCP connections and 0 HTTP requests**.
  The TCP test now counts connections, not just HTTP handler invocations.
- The existing recovery-test multithreaded `fork()` DeprecationWarning remains
  visible; the test passes.
- Full harness log SHA-256: `41ffc58fa06e209c4fb6b8c48ba85793544298790a14a8718c1894726dc4cadf`.
- Tools log SHA-256: `743be9f004f7ad3ae49f59b701e24f5eba0b77af554613eabbae8ed7f78b8fe2`.

NOT RUN: live Claude/Marty calls or paid APIs, registered question inputs,
the registered benchmark or section 2.4 dry run, alternate OS/WebKit hosts,
full engine/app builds, and the whole-tree manifest checker that would open
forbidden inputs. RUN-LOCK remains DRAFT and byte-unchanged; locked inputs and
prompts remain unchanged. FILES.json updates are limited to explicitly changed
files, preserving all other entries and their order.

## PR 75 response-policy revision: 2026-11-13 UTC

Status: **VERIFIED focused and full-suite synthetic checks.
Independent review and renderer selection remain PENDING.**
Checked: 2026-11-13T07:15:25Z on the Mac mini.
Source baseline: `b62f542b7c902e0b209c294f65107d10c6f35872`; implementation and
test source SHA-256 values:

- `render.swift`: `493bcbc157e62925209ffb357892770fa16855fee85bfc70cd94ff3a1f6652ca`
- `../tests/test_arm2_renderer.py`: `7465a55098817c0f8469db8470d065b9cfd954c4900c0b9778738039b9dbc427`
- `../tests/arm2_tokenizer_cases.py`: `1f8243739c1a736ba6fcace8e3dbc7cbc7dbf613710169e4c0f9bcb90eb12304`
- `../tests/fixtures/arm2/unquoted-attribute-quote.html`: `3f0894e823cef0ee3be93525964579f8cc2704e699a109de915aa1412e715f79`
- Renderer executable: `b90a03eb78642ef7537fd0781cc2cc3b69296707e7c0153cca455a8446007e64`

The existing custom-scheme handler now delivers the exact previous CSP string
as the document's `Content-Security-Policy` HTTP response header. It serves
authored UTF-8 bytes unchanged; loaded/source hashes match. The scanner and
HTML policy/map/checkpoint insertion have been deleted. The import map is
inserted by a main-frame document-start `WKUserScript` in the isolated client
world directly under the document element, without finding or creating a head.
On this host, WebKit honors that map for the first authored module's static
`import {REVISION} from 'three'`: revision 170 loads successfully. The
byte-zero response-body fallback was therefore not needed or implemented.

A document-start `data:` script canary requires a trusted enforcing CSP
violation with the exact policy and script directive. Its asynchronous evidence
and the exact connected map must pass an isolated native post-load check before
capture; absent evidence fails within five seconds. The legacy invariant report
fields are retained, with the document-start field set when that canary completes,
not claimed to be an event delivered before authored code. A DOM mutation
observer also checks the map after verification. Header policy is independent
of subsequent head edits. WebRTC native disable/readback, frame/worker
restrictions, readiness/render timeouts, frame counts and reports are retained.

The focused gated run passed **5 methods in 33.501 seconds**: WebGL cube,
the unquoted-attribute-quote first-script regression, map removal and two
fault-injected builds (missing response header; missing map insertion).
Both successful pages rendered **300 frames**. The first authored classic
script attempts a `data:` fetch and records a trusted `connect-src` violation;
this is distinct from the native script canary and cannot pass on that canary's
event. The first authored module resolves pinned three.js. All three refusal
cases returned **0 frames** and the explicit error
`head invariant: response CSP canary or document-start import map missing/changed`.
The fault pages also attempt to spoof the verifier and dispatch an exact-policy
but untrusted CSP event; neither bypasses the native gate.

Focused log SHA-256: `f1e1e934bad73ccb5b8988f5d5cf5bd6539bf96a227ef24fd39d44ca2a3a176b`.
Host: Mac mini, macOS 27.2 build 26B123, WebKit `22625.2.8.11.9`;
Python 3.14.10 and NumPy 2.5.4. Compilation, renderer runs and the harness suite
use the shared mini heavy-job gate, including its queue waits.

The 21 existing head cases remain. The reviewer's 39 tokenizer prefixes are
retained in `arm2_tokenizer_cases.py`; their page-side probes now check the
document-start map and actual module resolution, not a CSP meta element that
no longer exists. The separate first-script regression checks real CSP
enforcement rather than the presence of a DOM node.

The final gated full harness discovery ran **252 tests: 213 passed, 39 skipped,
zero failures/errors, 846.182 seconds**. The baseline was 249 (210 passed and
the same 39 skips); three new test methods cover the matrix and the two
configuration-omission builds. The first-script regression replaces the old
scanner-misplacement refusal test; the map-removal test replaces DOM policy
removal, since a response header is not removable through the DOM.

- All **21 original head cases** rendered **300 frames**, with both invariant
  fields true and pinned static module imports resolved.
- The **39-case reviewer matrix** produced **37 complete 300-frame renders**
  and **2 explicit zero-frame readiness timeouts** for unterminated comments
  that consume the authored readiness script. All 39 reports verified policy
  and map at document start and after load. The legacy `later-remove-policy`
  page records an authored null-node exception because its old meta node no
  longer exists; it still renders under the immutable response policy.
- The first-script quote regression again rendered **300 frames** and recorded
  the distinct trusted `connect-src` block before readiness. Map removal and
  both omitted-configuration builds again refused with **0 frames** and the
  explicit invariant error, not a successful partial render.
- The offline-network regression and matrix listeners recorded **0 accepted
  TCP connections and 0 HTTP requests**. The WebRTC regression recorded
  **0 UDP datagrams**, with main-frame, iframe and srcdoc probes retained.
- The WebGL cube rendered **300 frames** with distinct frame-0/frame-30 pixel
  payloads and sampled non-modal fractions of **17.17–19.38%**.
- Tools discovery: **52 tests, 51 passed, 1 skipped**, **2.635 seconds**.
  This lightweight suite does not invoke a real compiler or renderer.

The 39 harness skips are unchanged host/dependency limits: 16 require Linux
bubblewrap and node, 14 require bubblewrap for isolated fake CLIs, 3 require
the Linux G1 sandbox, and 6 lack the pinned Gemini CLI. The tools skip is
`setup.sh tools not installed`. Every macOS renderer/native-media test ran.
The existing multithreaded `fork()` DeprecationWarning remains visible; its
test passes. No skipped test is counted as a pass.

Full harness log SHA-256:
`e407f1c613e015dac29bf80f54bbb1be2b3951d9eaa7ad5fa18feb27e9b7e609`.
Tools log SHA-256:
`897491c07a774c9151cab02cb600bda266a43a80f9db9c2229b3ca64413a1da3`.
Static audit log SHA-256:
`88b234417fe377aea1d1a8de0f59dd2ed373300389a4b972180a64f3aae36b4e`.
That audit compares the exact policy/import-map strings, WebRTC preference
block, asset loader and capture/report implementation to the source baseline,
and confirms all 39 reviewer prefixes are unchanged with a common early-script
substitution. The policy/map strings and those unrelated implementation blocks
are byte-identical; no scanner/meta insertion remains.

NOT RUN: live model calls or paid APIs, registered question inputs, the
registered benchmark or section 2.4 dry run, alternate OS/WebKit hosts,
full engine/app builds, and the whole-tree manifest checker that would open
forbidden inputs. RUN-LOCK remains DRAFT and byte-unchanged. Locked inputs and
prompts are unchanged. FILES.json changes only explicit changed-path hashes
and appends new paths without reordering or rewriting other entries.
