// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlanceBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GlanceBar",
            targets: ["GlanceBarApp"]
        ),
        .library(
            name: "GlanceBarCore",
            targets: ["GlanceBarCore"]
        )
    ],
    targets: [
        .target(
            name: "GlanceBarCore"
        ),
        .executableTarget(
            name: "GlanceBarApp",
            dependencies: ["GlanceBarCore"]
        ),
        .testTarget(
            name: "GlanceBarCoreTests",
            dependencies: ["GlanceBarCore"]
        ),
        .testTarget(
            name: "GlanceBarAppTests",
            dependencies: ["GlanceBarApp"]
        )
    ]
)
