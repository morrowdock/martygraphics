// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "MartyPathTrace",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "marty-pathtrace", targets: ["MartyPathTrace"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .executableTarget(name: "MartyPathTrace",
                          dependencies: [.product(name: "MartyGraphicsPathTracer", package: "MartyGraphics")])
    ],
    swiftLanguageModes: [.v5]
)
