// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "TestPilot",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "TestPilotKit", targets: ["TestPilotKit"]),
        .executable(name: "testpilot", targets: ["testpilot"]),
    ],
    dependencies: [
        .package(url: "https://github.com/fjcaetano/openai-kit", branch: "main"), // TODO: use version
        .package(url: "https://github.com/yonaskolb/XcodeGen", from: "2.0.0"),
        .package(url: "https://github.com/Adorkable/swift-log-format-and-pipe", from: "0.1.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "TestPilotKit",
            dependencies: [
                .product(name: "OpenAIKit", package: "openai-kit"),
            ]
        ),
        .executableTarget(
            name: "testpilot",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LoggingFormatAndPipe", package: "swift-log-format-and-pipe"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "XcodeGenKit", package: "XcodeGen"),
                .product(name: "ProjectSpec", package: "XcodeGen"),
            ]
        )
    ]
)
