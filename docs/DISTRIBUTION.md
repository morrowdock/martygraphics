# Versioned installation and discovery

Status: release preparation. The public baseline is
`55c98121766c8a079006ee3106289ee97c30e7cd`. No package tag or GitHub release existed
when checked on 2026-11-04. **A remote SPM install at a reviewed semver tag is not
verified yet.** Protocol `v: 1` does not imply a package version. Do not substitute
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
   against the tag/approved commit. The program below parses and applies the
   public grammar examples; it must exit successfully. A cached checkout alone
   is not evidence of a working integration. This small smoke test is also not
   independent adopter or accessibility acceptance.
5. **Review the receipt before distribution.** Preserve exact tag/commit,
   `Package.swift`, `Package.resolved`, source, OS/Swift/configuration, commands,
   exits and stdout in private evidence. Publish only reviewed, sanitized results.
   A new candidate/version needs its own evidence. Until this receipt exists,
   versioned remote installation remains pending.

Remote client's `Sources/<executable>/main.swift` (for the post-tag smoke test;
not a claim that it has run):

```swift
import Foundation
import MartyGraphics

let envelope = try JSONSerialization.jsonObject(
    with: Data(MGGrammar.sceneExample.utf8)) as! [String: Any]
let patchEnvelope = try JSONSerialization.jsonObject(
    with: Data(MGGrammar.patchExample.utf8)) as! [String: Any]
let scene = try MGParser.scene(object: envelope["scene"]!).get()
let patch = try MGPatch.parse(object: patchEnvelope["patch"]!).get()
let updated = try scene.applying(patch).get()
precondition(updated.title == "Synthetic dot" && updated.revision == 1)
print("MartyGraphics remote scene/patch smoke passed")
```

The local protocol fixture test checks the corresponding JSON and selected
failure reasons. It does not replace the remote client's resolution/build/run.

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
