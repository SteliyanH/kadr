// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kadr",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
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
