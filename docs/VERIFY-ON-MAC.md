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

The Ubuntu workflow checks repository hygiene and DCO. It does not execute
these Apple-framework build/tests. Record a successful Mac run at the exact
release commit before publication. These tests do not establish visual
quality on a physical iPhone/iPad or cover every possible scene.
