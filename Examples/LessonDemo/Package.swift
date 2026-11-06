// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Host example: the beat-by-beat rotation lesson on the public MartyGraphics lesson API.
// `LessonDemoKit` is example code (fixture, demo view, headless verify and timing); it is not part of the engine.
let package = Package(
    name: "LessonDemo",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "LessonDemoKit", targets: ["LessonDemoKit"]),
               .executable(name: "lesson-demo", targets: ["LessonDemo"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .target(name: "LessonDemoKit", dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")]),
        .executableTarget(name: "LessonDemo", dependencies: ["LessonDemoKit", .product(name: "MartyGraphics", package: "MartyGraphics")]),
        .testTarget(name: "LessonDemoKitTests", dependencies: ["LessonDemoKit", .product(name: "MartyGraphics", package: "MartyGraphics")])
    ],
    swiftLanguageModes: [.v5]
)
