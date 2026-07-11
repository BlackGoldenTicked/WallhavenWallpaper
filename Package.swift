// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WallhavenWallpaper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WallhavenWallpaper", targets: ["WallhavenWallpaper"])
    ],
    targets: [
        .executableTarget(
            name: "WallhavenWallpaper",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
