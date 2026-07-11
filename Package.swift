// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MouseIncMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MouseIncCore", targets: ["MouseIncCore"]),
        .executable(name: "MouseIncMac", targets: ["MouseIncMac"])
    ],
    targets: [
        .target(name: "MouseIncCore"),
        .executableTarget(
            name: "MouseIncMac",
            dependencies: ["MouseIncCore"]
        ),
        .executableTarget(
            name: "MouseIncCoreCheck",
            dependencies: ["MouseIncCore"]
        ),
        .testTarget(
            name: "MouseIncCoreTests",
            dependencies: ["MouseIncCore"]
        ),
        .testTarget(
            name: "MouseIncMacTests",
            dependencies: ["MouseIncMac", "MouseIncCore"]
        )
    ]
)
