// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kadr",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Kadr", targets: ["Kadr"]),
    ],
    targets: [
        .target(
            name: "Kadr",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KadrTests",
            dependencies: ["Kadr"],
            resources: [.process("Resources")]
        ),
    ]
)
