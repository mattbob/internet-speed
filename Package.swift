// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InternetSpeedCore",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "InternetSpeedCore",
            targets: ["InternetSpeedCore"]
        ),
    ],
    targets: [
        .target(
            name: "InternetSpeedCore",
            path: "InternetSpeedCore/Sources/InternetSpeedCore"
        ),
        .testTarget(
            name: "InternetSpeedCoreTests",
            dependencies: ["InternetSpeedCore"],
            path: "InternetSpeedCore/Tests/InternetSpeedCoreTests"
        ),
    ]
)
