// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceControlSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "VoiceControlSDK",
            targets: ["VoiceControlSDK"]
        ),
    ],
    targets: [
        .target(
            name: "VoiceControlSDK",
            path: "Sources/VoiceControlSDK"
        ),
        .testTarget(
            name: "VoiceControlSDKTests",
            dependencies: ["VoiceControlSDK"],
            path: "Tests/VoiceControlSDKTests"
        ),
    ]
)
