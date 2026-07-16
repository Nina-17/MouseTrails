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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .target(name: "MouseIncCore"),
        .executableTarget(
            name: "MouseIncMac",
            dependencies: [
                "MouseIncCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
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
