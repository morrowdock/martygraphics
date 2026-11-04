# Third-party inventory

This source package declares **no external package dependencies** and vendors
no third-party source, fonts, images, model weights, or binary assets. The committed
PNG/GIF showcase assets are original synthetic renders of this package, under
Apache-2.0; their source and hashes are in [the capture receipt](assets/native/provenance.json).

| Component | Use | License / source |
| --- | --- | --- |
| Swift 6 standard library / toolchain | Build and runtime platform | Apache-2.0 with Swift Runtime Library Exception; https://github.com/swiftlang/swift/blob/main/LICENSE.txt |
| Foundation, SwiftUI, Combine, SceneKit, CoreGraphics, simd; AppKit, ImageIO, UniformTypeIdentifiers in the macOS showcase | Installed Apple platform SDKs | Platform frameworks, not redistributed by this repository; macOS/iOS SDK terms apply |
| XCTest | Platform test framework | Toolchain/SDK component; not vendored |
| Python 3 standard library | Optional DCO workflow helper | PSF-2.0; https://docs.python.org/3/license.html |
| actions/checkout | CI only | MIT; https://github.com/actions/checkout/blob/main/LICENSE |
| Contributor Covenant 2.1 | CODE_OF_CONDUCT.md | CC-BY-4.0; https://github.com/ContributorCovenant/contributor_covenant/blob/91532d80ea5f39b6685aff4892bc6854bf2f6d6f/LICENSE.md ; attribution retained in the document |

CI actions are pinned to immutable commit SHAs in the workflow. Apple frameworks
are platform dependencies, not separately licensed open-source redistributions.
No GPL, AGPL, or MPL package is included. Package.swift has no dependencies list.
No third-party binary redistribution has been approved by this source inventory.

Contributor Covenant 2.1 was taken from the CC-BY-4.0 snapshot 91532d80ea5f39b6685aff4892bc6854bf2f6d6f
(before the website repository changed its license). Only the enforcement contact
was substituted; original attribution is retained. No current website source code is bundled.
