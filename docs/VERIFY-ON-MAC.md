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

### Default grammar digest under Darwin Foundation

`LessonCoreTests.testU16DefaultGrammarDocumentIsUnchanged`
(`Tests/MartyGraphicsTests/LessonCoreTests.swift`) recomputes the FNV-1a 64
digest and the byte count of the canonical default grammar document
(`MGGrammar.document()` written by `JSONSerialization` with sorted keys and
unescaped slashes), prints them, and compares them with the pin (`grammarHash`,
`grammarBytes`). The pin was computed offline (a Python rebuild of the
document, and Linux `JSONSerialization`), never under Darwin Foundation, whose
`JSONSerialization` writes the bytes on a Mac. Recompute it on the Mac, on its
own, from the clean checkout above (the log goes outside the checkout):

```sh
swift test --filter 'MartyGraphicsTests.LessonCoreTests/testU16DefaultGrammarDocumentIsUnchanged' 2>&1 \
  | tee "${TMPDIR:-/tmp}/mg-grammar.log" | grep -E 'grammar digest|byte count|Executed'
```

Expected with sliders, readouts, curves, and math text: the line
`grammar digest 562c1edca6aa489c byte count 4416`, and the test passes.
Record the commit, that line and the result. A different digest or byte count
fails the test, and its message repeats them. Then update `grammarHash` and
`grammarBytes` to the Darwin values in a reviewed commit that names the old and
the new values, and run the step again; never change the pin without that
review. The full `swift test` run below covers the same test, so this step only
puts the digest in the record.

Sibling branches change the same document, so an expected value belongs to one
commit: the parametric and polar curves (`feat/param-polar`) pin
`9e03a7f5a9064722` against an older main. Branches land one at a time, and each
lands with its pin recomputed for the document as merged (offline first, then by
this step on the Mac), never with a value copied from another branch: the value
above is the document with the learner sliders (#107) and the readouts.

The root package test run does not build or test the other packages. Every
folder of the checkout with a `Package.swift` is a package, except under a
`.build` folder (at any depth) or under the vendor roots `vendor` and
`third_party` at the top of the checkout; list them with
`git ls-files '*Package.swift'` and drop those. `tools/render-blender` has no
`Package.swift` but is verified natively too, on a host with the pinned Blender
([setup](../tools/render-blender/README.md)).

These are the native commands of every package, in order, under a `#` line
naming the package. They are `PACKAGE_COMMANDS` in `tools/validate_local.py`,
which the receipt writer runs; a test keeps the two identical. `NEW_EXPORT_DIR`
is a new directory outside the checkout (export refuses an existing one). It may
appear only as the argument right after `--export` in `Examples/Showcase`; the
receipt writer refuses to run anything when it appears anywhere else. A
package that is not listed yet runs `swift test --jobs 2 --package-path P` when
`P/Tests` exists and `swift build --jobs 2 --package-path P` otherwise, with `P`
as one argument even when it contains a space (quote it in a shell); add it here
and to `PACKAGE_COMMANDS`.

```sh
# .
swift build
swift test
# Examples/KeySwitch3D
swift test --jobs 2 --package-path Examples/KeySwitch3D
# Examples/LessonDemo
swift test --jobs 2 --package-path Examples/LessonDemo
# Examples/PathTrace
swift build --jobs 2 --package-path Examples/PathTrace
# Examples/Showcase
swift build --jobs 2 --package-path Examples/Showcase
swift run --skip-build --package-path Examples/Showcase marty-showcase --verify
swift run --skip-build --package-path Examples/Showcase marty-showcase --export NEW_EXPORT_DIR
# Examples/Solid3D
swift test --jobs 2 --package-path Examples/Solid3D
# Examples/Turbofan
swift test --jobs 2 --package-path Examples/Turbofan
# tools/SceneValidator
swift test --jobs 2 --package-path tools/SceneValidator
swift build -c release --jobs 2 --package-path tools/SceneValidator
# tools/render-blender
tools/render-blender/selftest.sh
```

Record each present package's results separately in the exact-source receipt,
in the [native receipt](LOCAL-VALIDATION.md#native-evidence-and-publishing)
format. The writer does all of this from a clean checkout and writes that
receipt to a new path outside the checkout:

```sh
python3 tools/write_native_receipt.py /absolute/path/native-receipt.json
```

It refuses a checkout with any change or untracked file and pins the full
`HEAD` SHA as `"source"`. It finds the packages with the same rule (and the same
code) as the reuse check in `validate_local.py`, runs the commands above for each
package in order (`NEW_EXPORT_DIR` becomes a new `-showcase-export` folder named
after the receipt, beside it), and records the exit code of each package's first failing
command, or 0 when all of them pass; a command that cannot start (no `swift`)
counts as 127. `tools/render-blender/selftest.sh` exits 127 when there is no
Blender executable, and 3 when `blender --version` does not report the pinned
5.2.4, even when `BLENDER` or `BLENDER_VERSION` points elsewhere; either one is a
failed package, never a skip. It refuses to write a
receipt when the commands changed `HEAD` or `git status --porcelain`, and it
exits non-zero when any package failed. The receipt is version 2: each package
entry records the argv lists it ran as `commands` (with `NEW_EXPORT_DIR` kept as
that token) next to `exit`, and `commands_sha256` covers all of them. Keep its
complete output and exit code beside the receipt.

A missing command or failed check cannot be replaced by an older receipt
that did not cover that package. These builds and tests are not a visual or
interaction check; those still require an approved native preview.

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
PR head SHA, not the synthetic merge. The `macos` check is a short
Ubuntu job that passes only when all four `macos-<shard>` jobs pass. The shards
run at the same time on the free standard `macos-26` image (Xcode 26.6), each
with `--jobs 2`:

| Shard | Runs |
|---|---|
| `engine-solid` | root package tests whose class starts with `Solid` (`--filter '^MartyGraphicsTests\.Solid'`) |
| `engine-rest` | `swift build` of the root package, all other root tests (`--skip` with the same pattern) and the Examples/LessonDemo tests on macOS (its iPad-simulator run stays local) |
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
