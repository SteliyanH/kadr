import Foundation
import CoreImage
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Built-in ``Compositor`` that masks a clip's frames using the alpha channel of a
/// supplied mask image. Pixels under fully-opaque mask alpha pass through; pixels under
/// fully-transparent mask alpha become transparent. Anti-aliased edges produce
/// proportional alpha — useful for soft-edge masks.
///
/// **Mask sizing.** The mask is stretched to the per-frame extent. If the mask's aspect
/// ratio doesn't match the source frame's, the mask distorts. Authoring masks at the
/// composition's preset resolution avoids this in practice.
///
/// Used by ``VideoClip/mask(_:)-(CIImage)`` and ``VideoClip/mask(_:)-(PlatformImage)``;
/// users don't construct it directly.
internal struct MaskCompositor: Compositor {
    let mask: CIImage

    func process(image: CIImage, context: CompositorContext) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        // Stretch the mask to fit the source frame's extent.
        let maskExtent = mask.extent
        let scaledMask: CIImage
        if maskExtent.size != extent.size && maskExtent.width > 0 && maskExtent.height > 0 {
            let sx = extent.width / maskExtent.width
            let sy = extent.height / maskExtent.height
            scaledMask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        } else {
            scaledMask = mask
        }

        // Fully-transparent background — pixels outside the mask become transparent.
        let transparent = CIImage(color: .clear).cropped(to: extent)

        let filter = CIFilter(name: "CIBlendWithAlphaMask")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        filter?.setValue(scaledMask, forKey: "inputMaskImage")
        return filter?.outputImage ?? image
    }

    /// Cross-platform `PlatformImage` → `CIImage` extraction. Used by the convenience
    /// `mask(_:)` modifier overload.
    internal static func ciImage(from platformImage: PlatformImage) -> CIImage? {
        #if canImport(UIKit)
        if let cg = platformImage.cgImage {
            return CIImage(cgImage: cg)
        }
        return CIImage(image: platformImage)
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: platformImage.size)
        guard let cg = platformImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return CIImage(cgImage: cg)
        #endif
    }
}
