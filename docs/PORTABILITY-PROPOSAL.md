# Proposal: a shared scene core with renderer adapters

Status: architecture proposal. **Portability implementation is planned-not-started.**
No Windows, browser or Linux support is claimed. No blanket rewrite is selected.

## Current dependency boundary

The package currently builds one target. SwiftUI/Combine host presentation and
control state; CoreGraphics provides geometry/layout types; SceneKit/simd and
AppKit/UIKit support 3D/platform integration. Model, validation, patches, streams,
templates and timeline semantics are mixed into that same Apple-targeted package.
Foundation/bridging and lock/registry behavior also need explicit portability tests.

Native iPad support does not inherently require an Apple-only core architecture.
The present renderers are Apple-specific because of their framework dependencies;
the core/adapter separation has not been implemented or validated here.

## A bounded proposal

1. **Map and test before moving files.** Inventory platform imports and public API
   types. Capture the current parser, reference, numeric, patch and stream semantics
   in original synthetic fixtures, including invalid inputs and rollback behavior.
2. **Candidate core boundary.** Evaluate scene/JSON models, validation, grammar,
   patch/stream processing, timeline and template/pack contracts independently of
   rendering. Treat CoreGraphics geometry, font measurement, global registry locks
   and host lifecycle as explicit seams rather than assuming they are portable.
3. **Preserve Apple integration.** Keep SwiftUI Canvas and SceneKit adapters and
   existing host APIs while a small core separation proves compatibility. A native
   renderer is not discarded just to make a browser proof of concept.
4. **Browser feasibility with the SAME protocol.** A browser renderer must consume
   the same versioned scene/patch format and shared fixture corpus. It must not
   quietly add a different set of meanings, bounds or commands under the same name.
   Evaluate a small renderer adapter or validated-core bridge; select neither a
   language rewrite nor WASM as a foregone conclusion.
5. **Parity before support claims.** For each shared fixture compare acceptance or
   rejection, reason category, resolved items/steps, computed values, revisions,
   timeline samples and failed-update rollback. Compare pixels/layout separately
   with documented tolerances for fonts, antialiasing and camera differences.
6. **Test targets independently.** Windows, browser and Linux each need their own
   build/runtime/security/accessibility evidence. One browser demo does not prove
   Windows native support, Linux support, or Swift running in the browser.

## Preserve constraints

Keep closed keys, finite ranges, item/text/step/byte limits, cycle rejection,
strict stream finalization and transactional patches. Larger scenes require the
same [evidence-led limit review](CAPABILITIES.md#bounds-are-part-of-the-contract)
as any other expansion. Untrusted scenes do not gain arbitrary code execution.

The first implementation proposal should choose a small module/API seam, list
affected consumers, show shared-fixture tests and state a rollback path. It needs
independent integration review before a scoped forward-port. Source ownership and
license/privacy exclusions still apply; no automatic private mirror is introduced.

## External comparison: facts and unknowns

[HeyClicky's official about page](https://www.heyclicky.com/about) advertises
macOS 14.2+ and Windows 10/11. Its [official changelog](https://www.heyclicky.com/changelog)
documents 2D/3D screen drawings in the October 23, 2026 Mac/Windows releases.
Those product-level facts do **not** establish its current internal renderer stack.
That architecture is unverified here; no inference from its historical code or
platform list is used as an implementation requirement.

The useful response is to document our own platform contract and demonstrate
quality/parity with evidence. No first-of-kind, uniqueness, superiority, learning
outcome or performance claim follows from the comparison.
