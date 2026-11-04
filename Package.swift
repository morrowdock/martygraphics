// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Standalone scene engine using Apple platform frameworks; no external packages.
let package = Package(
    name: "MartyGraphics",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MartyGraphics", targets: ["MartyGraphics"])],
    targets: [.target(name: "MartyGraphics"),
              .testTarget(name: "MartyGraphicsTests", dependencies: ["MartyGraphics"])],
    swiftLanguageModes: [.v5]
)
