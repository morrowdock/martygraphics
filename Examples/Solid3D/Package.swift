// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "MartySolid3D",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "marty-solid3d", targets: ["MartySolid3D"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .executableTarget(name: "MartySolid3D",
                          dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")],
                          resources: [.copy("Models")])
    ],
    swiftLanguageModes: [.v5]
)
