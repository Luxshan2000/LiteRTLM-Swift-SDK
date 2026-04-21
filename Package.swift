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
        // Built from https://github.com/google-ai-edge/LiteRT-LM via Bazel.
        .binaryTarget(
            name: "CLiteRTLM",
            path: "Frameworks/LiteRTLM.xcframework"
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
