# Versioned installation and discovery

Status: first release. The public baseline was
`55c98121766c8a079006ee3106289ee97c30e7cd`. No package tag or GitHub release existed
when checked on 2026-11-04. The first tag, `v0.1.0`, is made from the reviewed merge
commit of the pull request that adds the `v0.1.0` section to the
[changelog](../CHANGELOG.md); its GitHub release notes come from that section.
**A remote SPM install at that tag is not verified until the remote-consumer row
below has a receipt.** Protocol `v: 1` does not imply a package version. Do not substitute
an invented tag, an unreviewed branch or a local path dependency as release evidence.

Use the [local quickstart](../README.md#quick-start) today. The versioned Markdown
[protocol/API guide](PROTOCOL.md), [synthetic JSON fixtures](fixtures/v1),
[tutorial](GETTING-STARTED.md) and [platform/app matrix](CAPABILITIES.md) describe
the actual public engine. The [showcase](SHOWCASE.md) provides original native
stills/animations with source and capture receipts.

## Release and remote-install gates

The publication maintainer prepares the evidence and scoped PR. The release
coordinator owns the reviewed tag/release and authenticated status; independent
review applies to each candidate. No tag/release is created by this document.

### Reviewed-release checklist

Complete these rows in the coordinator's private release receipt, with exact
SHAs/links and command results. A checked declaration is not a substitute for
the evidence. This is the checklist, not an announcement of a release.

| Gate / owner | Required evidence before proceeding |
| --- | --- |
| Candidate scope — publication maintainer | Exact head and changed-file list; versioned protocol/API, public synthetic fixtures, limits and platform claims match source. No private imports or unapproved public forward-port. |
| Local validation — maintainer/native lane | Exact-head hygiene, sign-offs and privacy/history/asset review; root manifest JSON, Mac build/tests and any changed example execution. Confirm GitHub noreply author/committer metadata as well as DCO trailers. |
| Review/merge — coordinator | Independent final-head review and authenticated `maintainer/local-validation`; normal protected PR merge. No quota waiver or protection bypass. |
| Version decision — coordinator | Actual merged release commit, approved semantic version, changelog, API/protocol compatibility and license/dependency inventory. No version is assigned by this checklist. |
| Tag/release — coordinator | Explicit authorization and an actual immutable tag resolving to the reviewed commit; record both tag-object and peeled commit when annotated. No tag creation command is provided here. |
| Remote consumer — approved native lane | The command below resolves/builds/runs a new remote-only client; tag, resolved pin and dependency checkout all match the reviewed commit. Preserve the private receipt; a local path build does not satisfy this row. |
| DocC/SPI — publication maintainer | After the reviewed versioned release: scoped configuration proposal, verified Apple documentation build and archive review, then owner review of the actual submission packet. No external submission yet. |

1. **Validate the exact candidate on Mac.** Run `swift package dump-package`,
   parse its output as JSON, then `swift build && swift test`. Run showcase
   `--verify`; existing capture evidence can be reused only for unchanged source.
   Complete [local hygiene/privacy validation](LOCAL-VALIDATION.md), refresh
   `FILES.json`, and obtain independent exact-head review. Record toolchain,
   platform, command exits and test count; do not count Windows hygiene as a Swift build.
2. **Approve a real version.** The release coordinator records the chosen semantic
   version, reviewed commit, compatibility/changelog decision and release receipt.
   A release tag must resolve to that exact commit. Version/protocol compatibility
   and public-sync ownership follow [PUBLIC-SYNC.md](PUBLIC-SYNC.md).
3. **Exercise a clean remote client.** After that tag exists, use a fresh directory
   outside this checkout and the public URL
   `https://github.com/morrowdock/martygraphics.git`. In a macOS 14+ Swift 6
   executable package, declare `.package(url: ..., exact: ...)` with the **real
   reviewed version**, and the product `.product(name: "MartyGraphics", package:
   "martygraphics")`. No local override, path dependency or branch fallback.
4. **Resolve, compile and run.** In that client run `swift package resolve`,
   `swift build`, and `swift run`. Verify the resolved pin's version and revision
   against the tag/approved commit. The generated program parses and applies the
   public grammar examples; it must exit successfully. A cached checkout alone
   is not evidence of a working integration. This small smoke test is also not
   independent adopter or accessibility acceptance.
5. **Review the receipt before distribution.** Preserve exact tag/commit,
   `Package.swift`, `Package.resolved`, source, OS/Swift/configuration, commands,
   exits and stdout in private evidence. Publish only reviewed, sanitized results.
   A new candidate/version needs its own evidence. Until this receipt exists,
   versioned remote installation remains pending.

### Copyable remote-SPM smoke command — pending a real tag

On an approved **Mac**, with Git, Python 3.9+ and Swift 6, obtain these four
values from the coordinator: `MG_RELEASE_TAG` (existing reviewed tag),
`MG_RELEASE_SHA` (full reviewed commit), and `MG_INSTALL_EVIDENCE` (a new private
directory outside the checkout), plus `MG_DEVELOPER_DIR` (the canonical approved
Apple developer directory). Supported installation roots are
`/Applications/Xcode.app/Contents/Developer` and `/Library/Developer/CommandLineTools`;
custom roots or symlinks escaping the selected root fail closed. Set the values
in the operator shell, then run:

```sh
python3 tools/verify_release_install.py \
  --tag "${MG_RELEASE_TAG:?Set the actual coordinator-approved existing tag}" \
  --commit "${MG_RELEASE_SHA:?Set its full reviewed commit SHA}" \
  --output "${MG_INSTALL_EVIDENCE:?Choose a new private evidence directory}" \
  --developer-dir "${MG_DEVELOPER_DIR:?Select the canonical approved Apple developer directory}"
```

The [runner source](../tools/verify_release_install.py) contains the complete
generated `Package.swift` and Swift client. It accepts a semantic tag (optional
`v` prefix) and full commit; it cannot establish approval by itself. It checks the
public tag before and after the test and pins an exact package version. Every
child receives an explicit minimal environment: no parent HOME, PATH, tracing,
proxy, agent, token or toolchain overrides are inherited. It creates an empty
private HOME (including empty `.netrc`/Git/curl config and SSH directory), XDG,
temporary and SwiftPM cache/config/security directories; no real-home files are copied.

Direct Git uses `/usr/bin/git`; Swift and its SDK come only from the selected
validated Apple installation. Child PATH contains fixed system directories and
that toolchain's bin directory, with system Git first. An explicit validated
Git helper directory and Git environment configuration apply to both direct
Git and Git spawned by Swift: no system/user configuration, reset credential
helpers/extra headers/cookies, no interactive prompts, and HTTPS-only transport.
Swift's `--disable-netrc`/`--disable-keychain` are additional SwiftPM controls;
**they do not disable Git/libcurl's own netrc lookup**. The separate empty HOME
addresses that configuration path; it is not a blanket credential-isolation guarantee.

This is configuration isolation under the same operating-system account, not a
filesystem/network sandbox. Approved build code can still access account files
or OS services. The coordinator must trust the selected Apple installation.
Native Git/libcurl/Swift and SDK behavior under this environment has not been
executed by the offline regressions; compatible-host verification remains gated.
Missing tools/SDKs fail closed rather than inheriting extra environment settings.
No local dependency, branch fallback, extra dependency, status
publisher, tag creation or release command is included.

The runner checks `Package.resolved` and the fetched dependency's actual commit
before building, uses `--force-resolved-versions`, then runs the built smoke
client with `--skip-build`. Its only client operation is the original synthetic
scene/title-patch flow from `MGGrammar`, asserting the changed title/revision.
[SwiftPM's documented options](https://docs.swift.org/latest/documentation/packagemanagerdocs/swiftrun/)
describe the resolved-file and private configuration flags.

Output stays outside this repository: generated client source/manifest,
`Package.resolved`, per-command stdout/stderr and SHA-256 hashes, toolchain,
actual host/platform, runner hash, exits and `receipt.json`. Failed stages retain
a failure receipt (including a 600-second per-command timeout). Raw evidence may
contain local paths; do not publish it.
The runner is read-only toward GitHub and does not request publishing credentials.

Offline Python regressions check input bounds, missing/mismatched tags, bad
resolved pins, refusal to overwrite/use an unsupported host, poisoned HOME/netrc/
config/helper/tracing/PATH, trusted-path rejection and the environment contract
through Python stand-ins for a Swift process and its Git child. They are
**synthetic guard tests, not remote installation acceptance**. As of this
checkpoint, no real tag exists and the real command remains unexecuted.

The local protocol fixture test checks the corresponding JSON and selected
failure reasons. It does not replace the remote client's resolution/build/run.

The actual Mac package receipt at `e1367c946171584044bacf5649ec7f816ecb72ae`
(2026-11-04T03:37:50Z) records valid dump-package JSON, build and 24 tests/zero
failures, all exit 0, on macOS 26.6.2 arm64 / Apple Swift 6.3.3, debug, language
mode 5. This is local package validation only. Documentation/Python follow-ups
reuse it only after proving Swift/package/test/fixture bytes unchanged.

## Swift Package Index and DocC — after the release

The official [Add a Package requirements](https://swiftpackageindex.com/add-a-package)
call for a public repository, a valid root `Package.swift`, Swift 5+, a semantic
release tag, valid `swift package dump-package` JSON, compilation, and compatible
conduct. This package has a root Swift-tools-6.0 manifest using Swift language
mode 5; that declaration alone does not prove every required gate has passed.

**Do not add SPI/DocC configuration until the reviewed versioned release exists.**
Then prepare one scoped PR using the then-current official
[SPI documentation configuration](https://swiftpackageindex.com/swiftpackageindex/spimanifest/documentation/spimanifest/commonusecases)
and [Swift-DocC guidance](https://www.swift.org/documentation/docc/).
Verify the package product/target, supported Apple documentation build target,
public symbol coverage, tutorial/example links, licensing and generated output.
Keep private paths and app symbols out. Do not add an unneeded plugin/dependency
or promise Linux documentation compilation for this Apple-framework renderer.

Preparation decisions for that later configuration PR:

| Item | Concrete candidate / acceptance gate |
| --- | --- |
| Package/repository | `MartyGraphics`; public HTTPS `.git` URL above; actual reviewed semantic tag and commit from the release receipt. |
| Documentation target | Public library target/product `MartyGraphics`; exclude test/executable targets and private app symbols. Verify the available scheme and symbol graph at the actual tag. |
| Builder | Apple-compatible macOS destination and a Swift/Xcode version supporting the tools-6.0 manifest. No Linux-build or iOS-device claim follows from this choice. |
| Content | Public parser/grammar/patch/stream/layout/timeline/pack/view APIs; reuse the v1 guide and original JSON fixtures. Check signatures, main-actor requirements, error boundaries and all cross-links. |
| SPI configuration | Plan one root `.spi.yml` using the then-current official schema and `MartyGraphics` documentation target after the release gate. Review the actual file before adding it; none is installed by this preparation. |
| Generated archive | A real `.doccarchive`, readable API navigation, valid source/example links, no local/private symbols/URLs, no claimed platform coverage beyond tested output. |
| Submission packet | Actual repository/tag/commit, compile/dump-package/remote-consumer results, license/notice/conduct links, proposed configuration and archive review. Owner reviews before the official add-package flow. |

After release approval, in a clean checkout of the **actual reviewed tag**, the
following is the local DocC verification candidate. It has not been executed by
this preparation; confirm `MartyGraphics` appears in the scheme inventory first.
Apple documents this [archive-generation approach](https://developer.apple.com/documentation/xcode/distributing-documentation-to-other-developers).

```sh
(
  set -eu
  : "${MG_DOCC_EVIDENCE:?Choose a new private directory outside the checkout}"
  mkdir "$MG_DOCC_EVIDENCE"
  xcodebuild -version > "$MG_DOCC_EVIDENCE/xcode-version.txt"
  xcodebuild -list -json > "$MG_DOCC_EVIDENCE/schemes.json"
  python3 - "$MG_DOCC_EVIDENCE/schemes.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    inventory = json.load(stream)
schemes = [name for value in inventory.values() if isinstance(value, dict)
           for name in value.get("schemes", [])]
if "MartyGraphics" not in schemes:
    raise SystemExit("Expected public library scheme missing; inspect inventory")
PY
  xcodebuild docbuild -scheme MartyGraphics \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$MG_DOCC_EVIDENCE/DerivedData" \
    > "$MG_DOCC_EVIDENCE/docbuild.log" 2>&1
  find "$MG_DOCC_EVIDENCE/DerivedData" -type d -name '*.doccarchive' -print
)
```

Review the scheme inventory before the docbuild step, and record command exits
and archive digest in the private receipt. A successful command or found archive
does not establish complete symbol coverage or valid rendered links. No hosted
DocC URL or package badge may be advertised until it actually exists and is reviewed.

The owner reviews the actual release/install/configuration evidence and proposed
submission before anyone uses the official add-package flow. No submission,
package-page badge, hosted DocC URL, account, tracker or paid service is assumed.

## Crawlable website handoff

The existing website owner owns `/martygraphics`; this repository does not claim
that the route is deployed. Reuse the public showcase assets and JSON sources.
The page should contain static text for the engine's purpose, early-preview
status, platform limits and varied examples (algorithm, directed diagram, plot,
synthetic counts, motion), plus real captions, still alternatives and ordinary
links to the README, protocol/API guide, sources, license and contribution steps.
Important information must remain available without an animated/browser demo.
Label native offscreen exports separately from website recreations and concepts.

Review rendered HTML, links, no-JS content and narrow-width readability at the
actual route before calling it available or changing the repository homepage.
Preserve current ownership and avoid duplicate capture/marketing work. Social
posts/outreach and submissions need owner review of the actual material.
Discussions stays disabled.

An optional `llms.txt` could be a navigation convenience only; it is not required
for this delivery. [Google's AI-feature guidance](https://developers.google.com/search/docs/appearance/ai-features)
says no new machine-readable/AI text files are needed. Do not make indexing,
ranking or AI-inclusion guarantees. No new tracker or account spend is authorized.

Portable-core/browser architecture remains a [proposal](PORTABILITY-PROPOSAL.md);
implementation is planned-not-started. Discovery work does not expand supported
platforms or public app content.
