// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LiteRTLM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LiteRTLM", targets: ["LiteRTLM"]),
        .library(name: "LiteRTLMDownloader", targets: ["LiteRTLMDownloader"]),
    ],
    targets: [
        // Pre-built C framework from Google's LiteRT-LM.
        // Hosted as a GitHub release asset — SPM downloads it automatically.
        .binaryTarget(
            name: "CLiteRTLM",
            url: "https://github.com/Luxshan2000/LiteRTLM-Swift-SDK/releases/download/v0.1.0/CLiteRTLM.xcframework.zip",
            checksum: "PLACEHOLDER_CHECKSUM"
        ),

        // Main Swift SDK
        .target(
            name: "LiteRTLM",
            dependencies: ["CLiteRTLM"]
        ),

        // Model download & management (no C dependency)
        .target(name: "LiteRTLMDownloader"),

        // Tests
        .testTarget(
            name: "LiteRTLMTests",
            dependencies: ["LiteRTLM"]
        ),
        .testTarget(
            name: "LiteRTLMDownloaderTests",
            dependencies: ["LiteRTLMDownloader"]
        ),
    ]
)
