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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .target(
            name: "GlanceBarCore"
        ),
        .executableTarget(
            name: "GlanceBarApp",
            dependencies: [
                "GlanceBarCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])
            ]
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
