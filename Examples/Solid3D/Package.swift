// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "MartySolid3D",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "marty-solid3d", targets: ["MartySolid3D"]),
               .executable(name: "marty-solid", targets: ["MartySolidCLI"]),
               .library(name: "MartySolidGLTF", targets: ["MartySolidGLTF"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .executableTarget(name: "MartySolid3D",
                          dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")],
                          resources: [.copy("Models")]),
        .executableTarget(name: "MartySolidCLI",
                          dependencies: ["MartySolidGLTF", .product(name: "MartyGraphics", package: "MartyGraphics")]),
        // glTF 2.0 (.glb) export of a strictly checked document and its baked motion (docs/GLTF-EXPORT.md). Read-only:
        // it uses the engine's public API and changes no engine output.
        .target(name: "MartySolidGLTF",
                dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")]),
        // Runs the built `marty-solid` in fresh processes: exit codes, JSON output and refusal order across hash seeds.
        .testTarget(name: "MartySolidCLITests", dependencies: ["MartySolidCLI"]),
        .testTarget(name: "MartySolidGLTFTests",
                    dependencies: ["MartySolidGLTF", .product(name: "MartyGraphics", package: "MartyGraphics")])
    ],
    swiftLanguageModes: [.v5]
)
