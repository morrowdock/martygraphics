# Verify on Mac

Requires Swift 6 and macOS 14+; Windows builds are unsupported.
Apple SwiftUI, SceneKit, CoreGraphics, and Combine are required.
There are no external Swift package dependencies.

From a clean checkout of the exact commit being verified:

```sh
git rev-parse HEAD
git status --porcelain
swift --version
swift build && swift test
git status --porcelain
```

When the checkout includes `Examples/UnitCircle`, also build it and run its
geometry verification:

```sh
swift build --jobs 2 --package-path Examples/UnitCircle
swift run --skip-build --package-path Examples/UnitCircle unit-circle --verify
```

When it includes `tools/SceneValidator`, also run:

```sh
swift test --jobs 2 --package-path tools/SceneValidator
swift build -c release --jobs 2 --package-path tools/SceneValidator
```

Record each present package's results separately in the exact-source receipt.
The root package test run does not build or test these subpackages. A missing
command or failed check cannot be replaced by an older receipt that only covered
the engine. UnitCircle's geometry verification is not a visual or interaction
check; those still require an approved native preview.

Record the commit, macOS / Xcode / Swift versions, complete output, and exit
codes with the release evidence. All tests must pass; do not replace failures
with skips. No private fixture file, environment variable, app adapter,
simulator, or device is required.

Tests cover synthetic scenes, tree/array templates, strict validation,
patch revisions, streaming, layout, render scheduling, controller rollback,
pack registration, concurrent registration, and malformed template output.
Highlight regressions cover self-targets, direct and indirect cycles, long
acyclic chains, deep public-API chains, and cycles introduced by step edits
or patches. The standard mechanics math helpers have numerical checks;
there are no built-in mechanics walkthrough templates.

The Ubuntu `hygiene` job checks repository hygiene and DCO. The `macos` job
(see below) runs the build and tests on a hosted Mac. Record a successful Mac run at the exact
release commit before publication. These tests do not establish visual
quality on a physical iPhone/iPad or cover every possible scene.

## Hosted macOS run (maintainer dispatch)

`.github/workflows/ci.yml` is dispatch-only: no PR, fork, or push triggers, no
secrets, read-only token, exact head-SHA checkout, no caches. A maintainer runs it:

```sh
gh workflow run ci.yml --repo morrowdock/martygraphics --ref main \
  -f base_sha=<full base sha> -f head_sha=<full PR head sha>
gh run watch
```

Use the actual PR head SHA, not the synthetic merge. The `macos` job runs on the
free standard `macos-26` image (Xcode 26.6) and does `swift build --jobs 2`,
`swift test --jobs 2` for the root package, tests for Examples/Solid3D,
Examples/Turbofan, Examples/KeySwitch3D and tools/SceneValidator, and builds for
Examples/Showcase and Examples/PathTrace. Logs upload as the `macos-test-logs`
artifact. Several dispatches run in parallel, so they do not queue on one Mac.

Hosted VMs have no real Metal GPU. Tests that need one already `XCTSkip`
themselves (`MGRTRenderer.isSupported`); no test was weakened. A hosted pass
therefore does NOT replace local native receipts: GPU path-tracer checks and
iOS-simulator checks still require a local Mac receipt.
