// swift-tools-version: 6.2
// 6.2 is the real floor, not a preference: kadr's public types store
// UIImage / NSImage / CIImage in Sendable structs, and those types are only
// Sendable in the Xcode 26 SDKs. Under Xcode 16 (Swift 6.0 / 6.1) the build
// fails with Sendable errors; declaring 6.2 makes SwiftPM say so plainly.
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
        // Examples compile as a target so they cannot rot. They were plain
        // reference files, which meant nothing checked them against the API
        // they demonstrate — and v0.14 removed three deprecated symbols.
        .target(
            name: "KadrExamples",
            dependencies: ["Kadr"],
            path: "Examples",
            swiftSettings: [.swiftLanguageMode(.v6)]
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
