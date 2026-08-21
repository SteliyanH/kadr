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
        // Benchmarks are an executable rather than a test target: they are run
        // deliberately, on real hardware, not as part of `swift test`. Export
        // needs hardware encode, which hosted CI runners do not have.
        .executableTarget(
            name: "KadrBenchmarks",
            dependencies: ["Kadr"],
            path: "Benchmarks/KadrBenchmarks",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KadrTests",
            dependencies: ["Kadr"],
            resources: [.process("Resources")]
        ),
    ]
)
