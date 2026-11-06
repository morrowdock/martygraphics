// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Turbofan cutaway example. `MartySolidRT` bridges a solid-engine snapshot (MartyGraphics) to the path tracer
// (MartyGraphicsPathTracer); it lives here so neither library depends on the other. `TurbofanKit` holds the model
// JSON and its geometric checks.
let package = Package(
    name: "MartyTurbofan",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "marty-turbofan", targets: ["MartyTurbofan"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .target(name: "MartySolidRT",
                dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics"),
                               .product(name: "MartyGraphicsPathTracer", package: "MartyGraphics")]),
        .target(name: "TurbofanKit",
                dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")],
                resources: [.copy("Models")]),
        .executableTarget(name: "MartyTurbofan",
                          dependencies: ["MartySolidRT", "TurbofanKit",
                                         .product(name: "MartyGraphics", package: "MartyGraphics"),
                                         .product(name: "MartyGraphicsPathTracer", package: "MartyGraphics")]),
        .testTarget(name: "TurbofanTests",
                    dependencies: ["MartySolidRT", "TurbofanKit",
                                   .product(name: "MartyGraphics", package: "MartyGraphics"),
                                   .product(name: "MartyGraphicsPathTracer", package: "MartyGraphics")]),
    ],
    swiftLanguageModes: [.v5]
)
