# Maintainer validation without hosted CI

The required commit status is **`maintainer/local-validation`**. A trusted
maintainer publishes it for the **actual PR head SHA**, after reviewing local
evidence and the independent scoped review. Every new head needs its own status.
An old success, a synthetic merge check or an Actions quota failure cannot clear
the candidate. Branch protection, PR review and administrator enforcement remain
in effect; this process provides evidence for those gates.

The workflow is **manual `workflow_dispatch` only**, on hosted `ubuntu-latest`.
It has no automatic push/PR/fork trigger and no self-hosted runner. Maintainers
may opt in with full base/head SHA inputs; hosted execution is optional and does
not replace local evidence. Do not route public-fork jobs to a personal laptop.

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
  --native-source TESTED_NATIVE_SOURCE_SHA
```

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
git diff --exit-code TESTED_NATIVE_SOURCE_SHA HEAD_SHA -- Sources Tests Package.swift Examples/Showcase/Package.swift Examples/Showcase/Sources docs/fixtures Examples/UnitCircle/Package.swift Examples/UnitCircle/Sources tools/SceneValidator/Package.swift tools/SceneValidator/Sources tools/SceneValidator/Tests
```

The DCO checker validates full SHA arguments, checks **every** commit in
`BASE_SHA..HEAD_SHA` and does not skip contributor merge commits. Its regressions
include unsigned contributor commits/merges and a synthetic checkout merge outside
the explicit contributor range. SHA values are passed as separate arguments;
the optional hosted workflow pins them through quoted environment variables.

The file check covers manifest hashes, JSON syntax, source SPDX and relative file
links. It is not a privacy review, semantic renderer test or proof that a link's
anchor exists. Review the full-history privacy categories, all binary assets and
their metadata separately; retain that evidence beside the receipt.

## Native evidence and publishing

Run the [Mac commands](VERIFY-ON-MAC.md) plus showcase `--verify` and `--export`
on an approved native execution lane. A prior exact-source receipt can be reused
only when the final command above proves the engine, package definitions, tests,
showcase tool, scene and documentation-fixture bytes, UnitCircle package and scenes, and scene-validator
package, sources and tests unchanged. These checks include additions and removals,
so a receipt from before a package existed cannot vouch for its addition. A reused
receipt must actually cover every present package; byte equality alone cannot
establish that its tests were run. README-only changes remain hygiene/review work.
Preserve that original source SHA and
asset digests; do not relabel an old execution as a new build. A documentation/CI
change still needs its own local hygiene and independent scoped review.

The coordinator reviews the private receipt, Gitleaks/privacy results, native
evidence, asset provenance and independent exact-head review, then rechecks the
live PR head. It publishes `maintainer/local-validation` through an authenticated
operator outside candidate code. No publisher is provided in this checkout.
Missing or failed evidence stays pending/failing; a status is not a quota waiver.
