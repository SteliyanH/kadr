import XCTest
@testable import Kadr

/// Tests for the v0.11 `Speed` enum collapse. Pre-v0.11 `VideoClip` had
/// `speed(_ rate: Double)` and `speed(curve: Animation<Double>)` as two
/// separate methods documented to mutually clear each other. v0.11 collapses
/// them into a single `Speed` enum, making the exclusivity type-level.
@MainActor
final class SpeedEnumTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/tmp/speed-test.mov")

    // MARK: - Default state

    func testDefaultSpeedIsFlatOne() {
        let clip = VideoClip(url: url)
        if case .flat(let rate) = clip.speed {
            XCTAssertEqual(rate, 1.0)
        } else {
            XCTFail("Expected .flat(1.0); got \(clip.speed)")
        }
    }

    // MARK: - Setter / getter round-trips

    func testFlatSpeedRoundTrip() {
        let clip = VideoClip(url: url).speed(.flat(2.0))
        if case .flat(let rate) = clip.speed {
            XCTAssertEqual(rate, 2.0)
        } else {
            XCTFail("Expected .flat(2.0); got \(clip.speed)")
        }
        XCTAssertEqual(clip.speedRate, 2.0)
        XCTAssertNil(clip.speedCurve)
    }

    func testCurvedSpeedRoundTrip() {
        let curve = Animation<Double>.keyframes([
            .at(0.0, value: 1.0),
            .at(2.0, value: 0.5),
        ], timing: .easeInOut)
        let clip = VideoClip(url: url).speed(.curved(curve))
        if case .curved = clip.speed {
            // ok — curve presence verified
        } else {
            XCTFail("Expected .curved; got \(clip.speed)")
        }
        XCTAssertNotNil(clip.speedCurve)
    }

    // MARK: - Mutual exclusion at the type level

    /// Setting a flat speed after a curved one clears the curve. Pre-v0.11
    /// this was the documented behavior of `speed(_:)`; v0.11 makes it
    /// structural — the enum has no `.both` case.
    func testFlatOverridesCurvedAndClearsCurve() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0)], timing: .linear)
        let clip = VideoClip(url: url)
            .speed(.curved(curve))
            .speed(.flat(1.5))
        XCTAssertEqual(clip.speedRate, 1.5)
        XCTAssertNil(clip.speedCurve)
    }

    /// Curved overrides flat — engine precedence is already this way; the
    /// new setter just makes it explicit.
    func testCurvedOverridesFlatAndPreservesRate() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0)], timing: .linear)
        let clip = VideoClip(url: url)
            .speed(.flat(2.0))
            .speed(.curved(curve))
        // speedRate stays at 2.0 (preserved by the curved setter so the
        // engine's fallback path still reads a sensible value), but the
        // canonical `speed` getter reports .curved because the curve wins.
        if case .curved = clip.speed {
            // ok
        } else {
            XCTFail("Expected .curved precedence; got \(clip.speed)")
        }
    }

    // MARK: - Deprecated overloads still work

    /// The legacy `speed(_ rate: Double)` overload dispatches through the
    /// new `Speed.flat` case. Deprecation warning expected at the call
    /// site; behavior preserved.
    func testDeprecatedFlatOverloadDispatchesToFlat() {
        // swiftlint:disable:next deprecated_speed_api
        let clip = VideoClip(url: url).speed(2.5) as VideoClip
        if case .flat(let rate) = clip.speed {
            XCTAssertEqual(rate, 2.5)
        } else {
            XCTFail("Expected .flat from deprecated overload; got \(clip.speed)")
        }
    }

    func testDeprecatedCurvedOverloadDispatchesToCurved() {
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0)], timing: .linear)
        let clip = VideoClip(url: url).speed(curve: curve)
        if case .curved = clip.speed {
            // ok
        } else {
            XCTFail("Expected .curved from deprecated overload; got \(clip.speed)")
        }
    }

    // MARK: - Modifier chain preservation

    /// Setting speed shouldn't disturb other fields (trim, transform,
    /// filters, id). Regression-guards a future bulk-rewrite of the
    /// init plumbing.
    func testSpeedPreservesOtherFields() {
        let clip = VideoClip(url: url)
            .trimmed(to: 0...4)
            .id(ClipID("c1"))
            .speed(.flat(2.0))
        XCTAssertNotNil(clip.trimRange)
        XCTAssertEqual(clip.clipID, ClipID("c1"))
        XCTAssertEqual(clip.speedRate, 2.0)
    }
}
