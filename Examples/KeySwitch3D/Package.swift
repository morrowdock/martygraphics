// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Host example: a schematic key-switch assembly built on the public MartyGraphics API.
// `KeySwitchModel` is example logic (geometry, template, component notes); it is not part of the engine.
let package = Package(
    name: "KeySwitch3D",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "key-switch-3d", targets: ["KeySwitch3D"])],
    dependencies: [.package(name: "MartyGraphics", path: "../..")],
    targets: [
        .target(name: "KeySwitchModel",
                dependencies: [.product(name: "MartyGraphics", package: "MartyGraphics")]),
        .executableTarget(name: "KeySwitch3D",
                          dependencies: ["KeySwitchModel", .product(name: "MartyGraphics", package: "MartyGraphics")]),
        .testTarget(name: "KeySwitchModelTests",
                    dependencies: ["KeySwitchModel", .product(name: "MartyGraphics", package: "MartyGraphics")])
    ],
    swiftLanguageModes: [.v5]
)
