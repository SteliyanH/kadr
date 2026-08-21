import Foundation
import CoreMedia
import Kadr

/// Benchmarks for the three scenarios the v1.0 roadmap names: single-track
/// export, multi-track with `KadrVideoCompositor`, and keyframe-heavy
/// compositions.
///
/// **Why this exists.** v0.13 was an entire performance cycle claiming a 10–30%
/// export improvement. Nothing in the repository could verify that number, and
/// nothing could catch it regressing — the claim rested on profiled traces taken
/// once, by hand, on one machine. This makes the claim checkable and the
/// regression visible.
///
/// **Why it is not in CI.** Export needs hardware encode. The hosted runners are
/// virtual machines without it, which is the same reason the media tests skip
/// there. Run this locally before and after a performance change, or from the
/// nightly hardware job.
///
///     swift run -c release KadrBenchmarks
///     swift run -c release KadrBenchmarks --json > before.json
///     swift run -c release KadrBenchmarks --compare before.json
///
/// Always build `-c release`. A debug build measures the optimiser's absence.

struct Options {
    var json = false
    var comparePath: String?
    var iterations = 5
    /// Tolerated regression before `--compare` fails, as a fraction.
    var tolerance = 0.10
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while let arg = args.first {
        args.removeFirst()
        switch arg {
        case "--json": o.json = true
        case "--compare": o.comparePath = args.isEmpty ? nil : args.removeFirst()
        case "--iterations": if let n = args.first.flatMap(Int.init) { o.iterations = n; args.removeFirst() }
        case "--tolerance": if let t = args.first.flatMap(Double.init) { o.tolerance = t; args.removeFirst() }
        case "--help", "-h":
            print("""
            KadrBenchmarks — export-path benchmarks for the v1.0 performance claims.

              --json                 emit machine-readable results
              --compare <file>       compare against a previous --json run
              --iterations <n>       measured runs per benchmark (default 5)
              --tolerance <f>        regression tolerated by --compare (default 0.10)

            Build in release, or the numbers measure the missing optimiser:
              swift run -c release KadrBenchmarks
            """)
            exit(0)
        default:
            FileHandle.standardError.write("Unknown argument: \(arg)\n".data(using: .utf8)!)
            exit(2)
        }
    }
    return o
}

func exportOnce(_ video: Video) async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kadr-benchmark-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await video.export(to: url)
}

let options = parseOptions()
let harness = Harness(warmups: 1, iterations: options.iterations)
var results: [Harness.Result] = []

do {
    results.append(try await harness.measure("single-track export (5s)") {
        try await exportOnce(Fixtures.singleTrack(seconds: 5))
    })
    results.append(try await harness.measure("multi-track + compositor (4x3s)") {
        try await exportOnce(Fixtures.multiTrack(clips: 4, seconds: 3))
    })
    results.append(try await harness.measure("keyframe-heavy (120 keys, 5s)") {
        try await exportOnce(Fixtures.keyframeHeavy(keyframes: 120, seconds: 5))
    })
} catch {
    FileHandle.standardError.write(
        """
        Benchmark failed: \(error.localizedDescription)

        Exports need hardware encode. On a virtualised runner this is expected —
        run on real hardware, or from the nightly hardware job.

        """.data(using: .utf8)!
    )
    exit(1)
}

if options.json {
    let data = try JSONEncoder().encode(results)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
} else {
    print("")
    for r in results { print(r.line) }
    print("")
    if results.contains(where: { $0.spread > 0.25 }) {
        print("⚠︎ At least one measurement was noisy. Close other work before trusting these.")
    }
}

if let path = options.comparePath {
    let previous = try JSONDecoder().decode(
        [Harness.Result].self,
        from: Data(contentsOf: URL(fileURLWithPath: path))
    )
    var regressed = false
    print("Compared against \(path), tolerance \(Int(options.tolerance * 100))%:\n")
    for now in results {
        guard let before = previous.first(where: { $0.name == now.name }) else {
            print(String(format: "  %-38s (new)", (now.name as NSString).utf8String!))
            continue
        }
        let delta = (now.minSeconds - before.minSeconds) / before.minSeconds
        let mark = delta > options.tolerance ? "REGRESSED" : (delta < -options.tolerance ? "improved" : "unchanged")
        if delta > options.tolerance { regressed = true }
        print(String(format: "  %-38s %+6.1f%%  %@",
                     (now.name as NSString).utf8String!, delta * 100, mark))
    }
    print("")
    if regressed { exit(1) }
}
