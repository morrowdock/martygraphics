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
(see below) runs the build and tests on a hosted Mac. `hygiene` is a required
pull request check; `macos` runs on every pull request but does not block a merge. Record a successful Mac run at the exact release commit before
publication. These tests do not establish visual
quality on a physical iPhone/iPad or cover every possible scene.

## Hosted CI (required merge gate)

`.github/workflows/ci.yml` (workflow `CI`) runs on every pull request (opened,
synchronize, reopened, ready for review), on every push to `main`, and on manual
dispatch. Branch protection on `main` requires the **`hygiene`** check run and
the **`maintainer/local-validation`** status, and requires branches to be **up to
date before merging**. The **`macos`** check still runs on every pull request and
every push to `main`, but it is not required, so a slow hosted Mac never holds a
merge. Maintainers read its result, and fix or revert at once when it is red. `main` takes only squash merges of PRs, force pushes are
disabled, and the rules include administrators. It uses `pull_request`, never
`pull_request_target`: fork PRs run with a read-only token and no secrets. There
are no caches, and checkouts do not keep credentials. A new push to a PR cancels
that PR's older run.

Each job checks out the **actual head commit**, not the synthetic merge ref, so a
result names one real SHA. This is sound only because branches must be up to
date: the PR head then already contains the latest `main`. The push run on `main`
after each merge is a late safety net, not the gate. The DCO range is the PR base
to the PR head; for a push to `main` it is the previous tip to the new tip. A new
branch, or a base that is gone after a force push, checks the head commit only
(`HEAD^..HEAD`). That fallback can miss a missing sign-off on an earlier commit of
a multi-commit push; this is acceptable because `main` takes only squash merges,
force pushes are disabled and administrators are included, so such a push
cannot reach `main`. The `hygiene` job
runs `git diff --check`, the `tools/tests` suite, `check_dco.py` and
`validate_local.py --check-files`.

A maintainer can also dispatch a run. A dispatched run uses the workflow file of
the dispatched `--ref` and attaches its check runs to **that ref's tip SHA**, not
to `head_sha`. To publish the required checks on a PR head, dispatch with
`--ref <the PR branch>` and with `head_sha` equal to that branch's current tip:

```sh
gh workflow run ci.yml --repo morrowdock/martygraphics --ref <PR branch> \
  -f base_sha=<full PR base sha> -f head_sha=<full tip sha of that PR branch>
gh run watch
```

A run dispatched with `--ref main` never satisfies a PR's required checks; its
check runs land on `main`'s tip. A fork PR's branch is not in this repository,
so a dispatch cannot publish its checks; its `pull_request` run does that. When
`head_sha` differs from the dispatched ref's tip, the run still tests `head_sha`
as evidence only, and the `hygiene` job writes a warning that its check runs are
on the ref's tip. Use the actual
PR head SHA, not the synthetic merge. The required `macos` check is a short
Ubuntu job that passes only when all four `macos-<shard>` jobs pass. The shards
run at the same time on the free standard `macos-26` image (Xcode 26.6), each
with `--jobs 2`:

| Shard | Runs |
|---|---|
| `engine-solid` | root package tests whose class starts with `Solid` (`--filter '^MartyGraphicsTests\.Solid'`) |
| `engine-rest` | `swift build` of the root package and all other root tests (`--skip` with the same pattern) |
| `solid3d-golden` | the Examples/Solid3D golden-file test alone |
| `solid3d-rest` | the other Examples/Solid3D tests (`--skip` with the same pattern), tests for Examples/Turbofan, Examples/KeySwitch3D and tools/SceneValidator, and builds for Examples/Showcase and Examples/PathTrace |

Each `--filter` shard has a `--skip` partner with the same pattern, so every
test, a new one too, runs in exactly one shard. A `--filter` shard fails when it
runs no test. Inside a shard the tests run one at a time, as before (some tests
assert wall-clock limits). This takes about 13 minutes instead of about 43 in one
job. Logs upload as one `macos-test-logs-<shard>` artifact per shard.
Several dispatches run in parallel, so they do not queue on one Mac.

Hosted VMs have no real Metal GPU. Tests that need one already `XCTSkip`
themselves (`MGRTRenderer.isSupported`); no test was weakened. A hosted pass
therefore does NOT replace local native receipts: GPU path-tracer checks and
iOS-simulator checks still require a local Mac receipt wherever this page or
[local validation](LOCAL-VALIDATION.md) asks for one. The PR checks are required
in addition to those receipts, not instead of them.
