// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JevBassist",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "JevBassistCore", targets: ["JevBassistCore"]),
        .library(name: "JevBassistJev", targets: ["JevBassistJev"]),
        .library(name: "JevBassistMIDI", targets: ["JevBassistMIDI"]),
        .executable(name: "jev-bassist", targets: ["JevBassistCLI"])
    ],
    targets: [
        .target(name: "JevBassistCore"),
        .target(
            name: "JevBassistJev",
            dependencies: ["JevBassistCore"]
        ),
        .target(
            name: "JevBassistMIDI",
            dependencies: ["JevBassistCore"],
            linkerSettings: [.linkedFramework("CoreMIDI")]
        ),
        .executableTarget(
            name: "JevBassistCLI",
            dependencies: ["JevBassistCore", "JevBassistJev", "JevBassistMIDI"]
        ),
        .testTarget(
            name: "JevBassistCoreTests",
            dependencies: ["JevBassistCore"]
        ),
        .testTarget(
            name: "JevBassistJevTests",
            dependencies: ["JevBassistCore", "JevBassistJev"]
        ),
        .testTarget(
            name: "JevBassistMIDITests",
            dependencies: ["JevBassistMIDI"]
        )
    ]
)
