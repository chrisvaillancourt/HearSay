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
    ],
    targets: [
        .executableTarget(
            name: "MeetingRecorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "MeetingRecorderTests",
            dependencies: ["MeetingRecorder"]
        ),
    ]
)
