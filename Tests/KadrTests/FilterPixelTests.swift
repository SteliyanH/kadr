import Testing
import CoreImage
import CoreMedia
@testable import Kadr

/// Per-frame filter coverage that does **not** export.
///
/// The export-level filter tests (`FilterTests`) are skipped on CI: they
/// pre-render an intermediate file through `FilterProcessor` and the runner
/// cannot decode it back. See ``TestEnvironment`` for the full diagnosis.
///
/// That left the filter *maths* — the part that actually decides what a frame
/// looks like — unverified on every PR, which is the wrong half to lose. These
/// tests exercise `Filter.apply(to:)`, the same call `FilterProcessor` makes
/// inside `applyingCIFiltersWithHandler`, against a synthetic image. No asset,
/// no encode, no decode, so they run anywhere.
///
/// They do not replace the export tests: nothing here proves the filter is
/// wired into the composition or survives a round-trip to disk. That gap is
/// tracked in the repo's issues and is what a hardware runner would close.
struct FilterPixelTests {

    /// Software renderer explicitly: the GPU path is exactly what is missing on
    /// virtualised runners, and this suite exists to run there.
    private static let context = CIContext(options: [.useSoftwareRenderer: true])

    /// A 4x4 image of one colour — enough to sample, cheap to render.
    private func solid(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    /// Centre pixel, as 0...1 RGB.
    private func sample(_ image: CIImage) throws -> (r: Double, g: Double, b: Double) {
        var buffer = [UInt8](repeating: 0, count: 4)
        Self.context.render(
            image,
            toBitmap: &buffer,
            rowBytes: 4,
            bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(buffer[0]) / 255, Double(buffer[1]) / 255, Double(buffer[2]) / 255)
    }

    // MARK: - Each filter moves the pixel the way it claims to

    @Test func brightnessLiftsEveryChannel() throws {
        let base = try sample(solid(red: 0.5, green: 0.5, blue: 0.5))
        let lifted = try sample(Filter.brightness(0.3).apply(to: solid(red: 0.5, green: 0.5, blue: 0.5)))
        #expect(lifted.r > base.r)
        #expect(lifted.g > base.g)
        #expect(lifted.b > base.b)
    }

    @Test func negativeBrightnessDarkens() throws {
        let base = try sample(solid(red: 0.5, green: 0.5, blue: 0.5))
        let darkened = try sample(Filter.brightness(-0.3).apply(to: solid(red: 0.5, green: 0.5, blue: 0.5)))
        #expect(darkened.r < base.r)
    }

    @Test func monoCollapsesChannelsToOneValue() throws {
        // A saturated red must come out grey — all three channels equal.
        let out = try sample(Filter.mono.apply(to: solid(red: 0.9, green: 0.1, blue: 0.1)))
        #expect(abs(out.r - out.g) < 0.02)
        #expect(abs(out.g - out.b) < 0.02)
    }

    @Test func sepiaWarmsTowardRed() throws {
        // Sepia's whole point: red channel ends above blue on a neutral input.
        let out = try sample(Filter.sepia(intensity: 1.0).apply(to: solid(red: 0.5, green: 0.5, blue: 0.5)))
        #expect(out.r > out.b)
    }

    @Test func sepiaAtZeroIntensityIsCloseToIdentity() throws {
        let base = try sample(solid(red: 0.4, green: 0.6, blue: 0.8))
        let out = try sample(Filter.sepia(intensity: 0.0).apply(to: solid(red: 0.4, green: 0.6, blue: 0.8)))
        #expect(abs(out.r - base.r) < 0.03)
        #expect(abs(out.b - base.b) < 0.03)
    }

    @Test func saturationAtZeroGreys() throws {
        let out = try sample(Filter.saturation(0.0).apply(to: solid(red: 0.9, green: 0.2, blue: 0.2)))
        #expect(abs(out.r - out.g) < 0.02)
        #expect(abs(out.g - out.b) < 0.02)
    }

    @Test func saturationAboveOnePushesChannelsApart() throws {
        let base = try sample(solid(red: 0.7, green: 0.4, blue: 0.4))
        let out = try sample(Filter.saturation(1.8).apply(to: solid(red: 0.7, green: 0.4, blue: 0.4)))
        #expect((out.r - out.g) > (base.r - base.g))
    }

    @Test func contrastWidensTheGapBetweenLightAndDark() throws {
        // Asserted as *separation*, not against absolute values. CIColorControls
        // pivots in linear space, so a 0.7 sRGB input does not simply move above
        // 0.7 — an earlier version of this test asserted exactly that and was
        // wrong. What contrast guarantees regardless of colour space is that
        // light and dark end further apart than they started.
        let lightIn = try sample(solid(red: 0.7, green: 0.7, blue: 0.7))
        let darkIn = try sample(solid(red: 0.3, green: 0.3, blue: 0.3))
        let lightOut = try sample(Filter.contrast(1.5).apply(to: solid(red: 0.7, green: 0.7, blue: 0.7)))
        let darkOut = try sample(Filter.contrast(1.5).apply(to: solid(red: 0.3, green: 0.3, blue: 0.3)))

        #expect((lightOut.r - darkOut.r) > (lightIn.r - darkIn.r))
    }

    @Test func contrastBelowOneNarrowsTheGap() throws {
        let lightIn = try sample(solid(red: 0.7, green: 0.7, blue: 0.7))
        let darkIn = try sample(solid(red: 0.3, green: 0.3, blue: 0.3))
        let lightOut = try sample(Filter.contrast(0.5).apply(to: solid(red: 0.7, green: 0.7, blue: 0.7)))
        let darkOut = try sample(Filter.contrast(0.5).apply(to: solid(red: 0.3, green: 0.3, blue: 0.3)))

        #expect((lightOut.r - darkOut.r) < (lightIn.r - darkIn.r))
    }

    @Test func exposureBrightens() throws {
        let base = try sample(solid(red: 0.3, green: 0.3, blue: 0.3))
        let out = try sample(Filter.exposure(1.0).apply(to: solid(red: 0.3, green: 0.3, blue: 0.3)))
        #expect(out.r > base.r)
    }

    // MARK: - Chaining, in the order FilterProcessor applies it

    @Test func chainedFiltersApplyInOrder() throws {
        let image = solid(red: 0.5, green: 0.2, blue: 0.2)
        // mono then brightness: grey first, then lifted — channels stay equal.
        let chained = Filter.brightness(0.2).apply(to: Filter.mono.apply(to: image))
        let out = try sample(chained)
        #expect(abs(out.r - out.g) < 0.02)
        #expect(out.r > 0.2)
    }

    @Test func everyFilterCaseProducesARenderableImage() throws {
        // Guards the `ciFilterName` mapping: a typo there yields a nil CIFilter
        // and a blank frame, which no export-free assertion above would catch
        // for cases that have no simple directional expectation.
        let cases: [Filter] = [
            .brightness(0.1), .contrast(1.2), .saturation(0.8),
            .exposure(0.5), .sepia(intensity: 0.7), .mono,
        ]
        for filter in cases {
            let out = try sample(filter.apply(to: solid(red: 0.5, green: 0.5, blue: 0.5)))
            // A nil CIFilter renders as transparent black; any real filter on a
            // mid-grey input leaves something behind.
            #expect(out.r > 0.01 || out.g > 0.01 || out.b > 0.01, "\(filter) rendered empty")
        }
    }

    // MARK: - Animation sampling (what FilterProcessor does per frame)

    @Test func withScalarRebuildsTheSameCaseAtANewValue() throws {
        let dim = try sample(Filter.brightness(0.0).withScalar(-0.3).apply(to: solid(red: 0.5, green: 0.5, blue: 0.5)))
        let lift = try sample(Filter.brightness(0.0).withScalar(0.3).apply(to: solid(red: 0.5, green: 0.5, blue: 0.5)))
        #expect(lift.r > dim.r)
    }
}
