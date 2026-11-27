# Maintainer local validation

Two gates apply to every PR. The hosted `CI` workflow's check run **`hygiene`**
is required and runs automatically; its **`macos`** check also runs on every PR
but is not required ([hosted CI](VERIFY-ON-MAC.md#hosted-ci-required-merge-gate)).
The local evidence below is still required where this page and
[Verify on Mac](VERIFY-ON-MAC.md) ask for it: hosted VMs have no real GPU and no
iOS simulator lane, and they do not run Gitleaks or the privacy review.

The required commit status is **`maintainer/local-validation`**. A trusted
maintainer publishes it for the **actual PR head SHA**, after reviewing local
evidence and the independent scoped review. Every new head needs its own status.
An old success, a synthetic merge check or an Actions quota failure cannot clear
the candidate. Branch protection, PR review and administrator enforcement remain
in effect; this process provides evidence for those gates.

The workflow runs on `pull_request`, on push to `main` and on manual
`workflow_dispatch` (full base/head SHA inputs), on hosted `ubuntu-latest` and
`macos-26` runners. It never uses `pull_request_target` or a self-hosted runner;
fork PRs get a read-only token and no secrets. A hosted pass does not replace
local evidence. Do not route public-fork jobs to a personal laptop.

## Review and pin the candidate

From a trusted operator context, inspect the PR, record its `baseRefOid` and
`headRefOid`, and fetch those exact commits. Do not substitute `refs/pull/N/merge`
for the contributor head. Review changes to validators, workflows and dependency
definitions before running code. For untrusted forks, use an isolated disposable
environment with no personal checkout, credentials or private data; do not
automatically execute them on a maintainer machine.

For this public repository, fetching over HTTPS needs no credentials. Do not put
tokens in the checkout, Git remotes, receipt, or validation scripts. Remove
inherited credential environment variables before running candidate code. Keep
status-publishing credentials in the coordinator's separate trusted context.
`validate_local.py` uses no GitHub API or publishing command.

## Reproduce local hygiene

Install Python 3.9+, Git and a portable Gitleaks binary; verify the binary against
its upstream release checksum. Use a clean checkout of the pinned candidate.
Replace the uppercase placeholders with literal full SHAs and local paths:

```sh
python3 tools/validate_local.py --base BASE_SHA --head HEAD_SHA \
  --gitleaks /path/to/gitleaks --receipt /private/evidence/NEW-receipt.json \
  --native-source TESTED_NATIVE_SOURCE_SHA \
  --native-receipt /private/evidence/NATIVE-receipt.json
```

Leave out both `--native-*` arguments when no earlier native receipt is reused;
the receipt then records `"nativeReuse": null`.

On Windows, the equivalent entry point is `py -3.13 tools/validate_local.py` with
the same arguments on one line and an installed portable Gitleaks `.exe` path.
The receipt and redacted Gitleaks JSON must be **new paths outside the checkout**.
They are private operational evidence: the receipt records the exact host name,
platform, SHA, command argument arrays and exit codes. Do not commit the receipt
or machine paths into the public repository.

The runner executes these scoped checks, with no hosted service dependency:

```sh
git diff --check BASE_SHA HEAD_SHA
python3 -m unittest discover -s tools/tests -v
python3 tools/check_dco.py BASE_SHA HEAD_SHA
python3 tools/validate_local.py --check-files
gitleaks git . --log-opts=--all --redact --report-format json --report-path PRIVATE_NEW_REPORT
```

With `--native-source`, it also runs the native reuse check below and records
the result as `nativeReuse` in the receipt.

The DCO checker validates full SHA arguments, checks **every** commit in
`BASE_SHA..HEAD_SHA` and does not skip contributor merge commits. Its regressions
include unsigned contributor commits/merges and a synthetic checkout merge outside
the explicit contributor range. SHA values are passed as separate arguments;
the hosted workflow pins them through quoted environment variables.

The file check covers manifest hashes, JSON syntax, source SPDX and relative file
links. It is not a privacy review, semantic renderer test or proof that a link's
anchor exists. Review the full-history privacy categories, all binary assets and
their metadata separately; retain that evidence beside the receipt.

## Native evidence and publishing

Run the [Mac commands](VERIFY-ON-MAC.md) plus showcase `--verify` and `--export`
on an approved native execution lane, and `tools/render-blender/selftest.sh` on a
host with the pinned Blender. The native receipt is a private JSON file that names
the exact source and **each package** it built and tested, with that package's
overall exit code:

```json
{"source": "TESTED_NATIVE_SOURCE_SHA",
 "packages": [{"path": ".", "exit": 0}, {"path": "Examples/Solid3D", "exit": 0}]}
```

On the Mac, write it from a clean checkout of the tested commit with

```sh
python3 tools/write_native_receipt.py /absolute/path/native-receipt.json
```

which runs the [Mac package commands](VERIFY-ON-MAC.md) for every package and
exits non-zero when any failed. Keep the complete output beside it.
`validate_local.py` takes the package set from the repository, not from a list:
`.` (the root package), every other folder with a `Package.swift`, and
`tools/render-blender`, leaving out `.build` folders and the `vendor` and
`third_party` vendor roots. Everything is read from the two pinned commits'
Git objects, never from the working tree. A prior receipt can be reused only
when, between `TESTED_NATIVE_SOURCE_SHA` and `HEAD_SHA`:

- no native byte changed. Native bytes are the root `Package.swift`,
  `Package.resolved`, `Sources/` and `Tests/`; every file of the other packages and
  `tools/render-blender`; and the inputs that native builds and tests read from
  outside them: every `Examples/` folder without a `Package.swift` (such as
  `Examples/Explainers`), `docs/fixtures`, each existing file or folder that a
  Swift string literal in either commit names from the repository root (for
  example `docs/assets`, `docs/REASONS.md` and `CHANGELOG.md`), each folder or file
  a package manifest names outside the package's default layout (custom target
  paths, resources and local dependencies, vendored ones too), and the tracked
  target of every covered symlink. An input folder covers **every** file in it,
  Markdown too. Additions, removals and renames (case-only ones too) count, so a
  receipt from before a package or file existed cannot vouch for it. Other
  Markdown in a package outside its `Sources/` and `Tests/` is documentation;
- no covered symlink points outside the repository or at a path missing from its
  commit, and no manifest names a dependency outside the repository;
- the receipt names **exactly** the packages present at `HEAD_SHA` (same spelling,
  no extra entries), each with exit 0. Byte equality alone cannot establish that a
  package's tests were run.

The `nativeReuse` record lists the packages and the input paths, then the
reasons reuse fails, each separately: `changed` native paths, `links` (symlinks or
dependencies outside the tree), `missing` packages the receipt does not name,
`unexpected` receipt entries that are not packages at `HEAD_SHA`, and `failed`
entries with a non-zero exit. Any of them being nonempty fails the run, and the
runner then says to run the Mac checks at `HEAD_SHA` and rerun with
`--native-source HEAD_SHA --native-receipt` naming the new receipt. Other changes (README and other documentation, CI, `tools/*.py`)
remain hygiene/review work. Preserve that original source SHA and asset digests;
do not relabel an old execution as a new build. A documentation/CI change still
needs its own local hygiene and independent scoped review.

The coordinator reviews the private receipt, Gitleaks/privacy results, native
evidence, asset provenance and independent exact-head review, then rechecks the
live PR head. It publishes `maintainer/local-validation` through an authenticated
operator outside candidate code. No publisher is provided in this checkout.
Missing or failed evidence stays pending/failing; a status is not a quota waiver.
