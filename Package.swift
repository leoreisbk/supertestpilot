// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "TestPilot",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "TestPilotKit", targets: ["TestPilotKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/fjcaetano/openai-kit", branch: "main"),
    ],
    targets: [
        .target(
            name: "TestPilotKit",
            dependencies: [
                .product(name: "OpenAIKit", package: "openai-kit"),
            ]
        ),
    ]
)
