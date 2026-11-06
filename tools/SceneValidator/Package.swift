// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Command-line scene checker built on the public MartyGraphics parser. No external packages.
let package = Package(
    name: "MartySceneValidator",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "marty-scene-validate", targets: ["MartySceneValidate"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .target(name: "SceneValidatorCore",
                dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")]),
        .executableTarget(name: "MartySceneValidate", dependencies: ["SceneValidatorCore"]),
        .testTarget(name: "SceneValidatorCoreTests",
                    dependencies: ["SceneValidatorCore", "MartySceneValidate",
                                   .product(name: "MartyGraphics", package: "MartyGraphics")])
    ],
    swiftLanguageModes: [.v5]
)
