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
