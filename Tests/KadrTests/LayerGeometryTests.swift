import Testing
import AVFoundation
@testable import Kadr
import CoreGraphics
import CoreImage
import CoreMedia

/// Reading a layer instruction's transform and opacity back, the way
/// ``KadrVideoCompositor`` does before handing frames to a ``MultiInputCompositor``.
struct LayerGeometryTests {

    private func seconds(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

    private func layer() -> AVMutableVideoCompositionLayerInstruction {
        AVMutableVideoCompositionLayerInstruction()
    }

    @Test func emptyLayerIsIdentityAndOpaque() {
        let geometry = LayerGeometry(layer())
        #expect(geometry.transform(at: seconds(1)) == .identity)
        #expect(geometry.opacity(at: seconds(1)) == 1)
    }

    @Test func steppedTransformsHoldUntilTheNextOne() {
        let layer = layer()
        layer.setTransform(CGAffineTransform(translationX: 10, y: 0), at: seconds(1))
        layer.setTransform(CGAffineTransform(translationX: 20, y: 0), at: seconds(2))
        let geometry = LayerGeometry(layer)

        #expect(geometry.transform(at: seconds(0.5)) == .identity)
        #expect(geometry.transform(at: seconds(1.5)).tx == 10)
        #expect(geometry.transform(at: seconds(2)).tx == 20)
        #expect(geometry.transform(at: seconds(60)).tx == 20)
    }

    @Test func transformRampInterpolatesAndHoldsItsEnd() {
        let layer = layer()
        layer.setTransformRamp(
            fromStart: CGAffineTransform(translationX: 0, y: 0),
            toEnd: CGAffineTransform(translationX: 100, y: 50),
            timeRange: CMTimeRange(start: seconds(1), duration: seconds(2))
        )
        let geometry = LayerGeometry(layer)

        let middle = geometry.transform(at: seconds(2))
        #expect(abs(middle.tx - 50) < 0.001)
        #expect(abs(middle.ty - 25) < 0.001)
        #expect(geometry.transform(at: seconds(10)).tx == 100)
    }

    @Test func opacityRampInterpolatesAndSteppedOpacityHolds() {
        let layer = layer()
        layer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: .zero, duration: seconds(1)))
        layer.setOpacity(0.25, at: seconds(2))
        let geometry = LayerGeometry(layer)

        #expect(abs(geometry.opacity(at: seconds(0.5)) - 0.5) < 0.001)
        #expect(geometry.opacity(at: seconds(1.5)) == 0)
        #expect(geometry.opacity(at: seconds(3)) == 0.25)
    }

    /// Placement conjugates the top-left-origin layer transform into Core Image's
    /// bottom-left-origin space: a shift down in layer space is a shift down on screen.
    @Test func placeFlipsBetweenCoordinateSpaces() {
        let geometry = LayerGeometry(
            transforms: [.init(start: CGAffineTransform(translationX: 0, y: 30),
                               end: CGAffineTransform(translationX: 0, y: 30),
                               range: CMTimeRange(start: .zero, duration: .positiveInfinity))],
            opacities: []
        )
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50))
        let placed = geometry.place(source, at: .zero, renderSize: CGSize(width: 100, height: 100))
        // Top edge 30 below the frame's top: bottom-up, it spans y 20...70.
        #expect(placed.extent == CGRect(x: 0, y: 20, width: 100, height: 50))
    }
}
