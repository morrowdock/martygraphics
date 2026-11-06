// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Standalone scene engine using Apple platform frameworks; no external packages.
// MartyGraphicsPathTracer is an additive, separate library (Metal ray tracing); the core
// MartyGraphics target does not depend on it.
let package = Package(
    name: "MartyGraphics",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MartyGraphics", targets: ["MartyGraphics"]),
               .library(name: "MartyGraphicsPathTracer", targets: ["MartyGraphicsPathTracer"])],
    targets: [.target(name: "MartyGraphics"),
              .testTarget(name: "MartyGraphicsTests", dependencies: ["MartyGraphics"]),
              .target(name: "MartyGraphicsPathTracer"),
              .testTarget(name: "MartyGraphicsPathTracerTests", dependencies: ["MartyGraphicsPathTracer"])],
    swiftLanguageModes: [.v5]
)
