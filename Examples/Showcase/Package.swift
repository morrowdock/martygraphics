// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "MartyShowcase",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "marty-showcase", targets: ["MartyShowcase"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .executableTarget(name: "MartyShowcase",
                          dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")],
                          resources: [.copy("Scenes")])
    ],
    swiftLanguageModes: [.v5]
)
