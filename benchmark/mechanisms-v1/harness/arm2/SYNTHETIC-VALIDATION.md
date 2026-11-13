# Synthetic validation: Arm 2 and recording shim

Status: **VERIFIED synthetic checks only. Renderer selection and A-17 remain
PROPOSED. No benchmark or section 2.4 dry run was performed.**

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
