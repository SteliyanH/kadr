import Foundation

/// Minimal measurement harness.
///
/// Deliberately not `package-benchmark`: that brings a dependency, a jemalloc
/// requirement, and a CI integration this package cannot use anyway — exports
/// need hardware encode, which the hosted runners do not have. What is needed
/// here is something a maintainer can run on a real machine before and after a
/// change, and that a nightly hardware job can run unattended.
///
/// Reports the **minimum** as the headline figure. A mean over a small sample
/// on a laptop measures background noise as much as the code; the fastest run
/// is the one least polluted by whatever else the machine was doing. Spread is
/// printed alongside so an unstable measurement is visible rather than hidden.
struct Harness {

    struct Result: Codable {
        let name: String
        let iterations: Int
        let minSeconds: Double
        let medianSeconds: Double
        let maxSeconds: Double

        /// How far the slowest run strayed from the fastest, as a fraction.
        /// Above ~0.25 the machine was busy and the numbers should not be
        /// compared against anything.
        var spread: Double { minSeconds > 0 ? (maxSeconds - minSeconds) / minSeconds : 0 }
    }

    let warmups: Int
    let iterations: Int

    init(warmups: Int = 1, iterations: Int = 5) {
        self.warmups = warmups
        self.iterations = iterations
    }

    func measure(_ name: String, _ body: () async throws -> Void) async rethrows -> Result {
        for _ in 0..<warmups { try await body() }

        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try await body()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000_000)
        }
        samples.sort()
        return Result(
            name: name,
            iterations: iterations,
            minSeconds: samples.first ?? 0,
            medianSeconds: samples[samples.count / 2],
            maxSeconds: samples.last ?? 0
        )
    }
}

extension Harness.Result {
    var line: String {
        let flag = spread > 0.25 ? "  ⚠︎ noisy" : ""
        return String(
            format: "%-38s min %7.3fs   median %7.3fs   max %7.3fs%@",
            (name as NSString).utf8String!, minSeconds, medianSeconds, maxSeconds, flag
        )
    }
}
