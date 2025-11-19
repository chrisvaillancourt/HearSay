// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MeetingRecorder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MeetingRecorder", targets: ["MeetingRecorder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // Using compatible versions that share swift-syntax 600.0.0
        .package(url: "https://github.com/realm/SwiftLint", exact: "0.58.1"),
        .package(url: "https://github.com/apple/swift-format", exact: "600.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingRecorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            exclude: [
                "Info.plist"
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint"),
            ]
        ),
        .testTarget(
            name: "MeetingRecorderTests",
            dependencies: ["MeetingRecorder"]
        ),
    ]
)
