import Foundation
import CoreImage

/// A built-in image filter applied per frame to a ``VideoClip`` at export time.
///
/// ```swift
/// VideoClip(url: clipURL)
///     .trimmed(to: 0...10)
///     .filter(.brightness(0.1))
///     .filter(.contrast(1.2))
///     .filter(.saturation(1.3))
/// ```
///
/// Filters chain in declaration order. Multiple filters can also be applied in one call:
///
/// ```swift
/// .filter(.brightness(0.1), .contrast(1.2), .saturation(1.3))
/// ```
///
/// Each filter wraps a `CIFilter` from CoreImage. Parameter ranges follow the underlying
/// CIFilter conventions; values outside the documented range are passed through and
/// generally clamped by CoreImage internally.
public enum Filter: Sendable, Equatable {
    /// Brightness adjustment. Range: `-1.0` (black) to `1.0` (white). `0` is unchanged.
    /// Maps to `CIColorControls.inputBrightness`.
    case brightness(Double)

    /// Contrast adjustment. Range: `0.0` (gray) to `~4.0`. `1.0` is unchanged.
    /// Maps to `CIColorControls.inputContrast`.
    case contrast(Double)

    /// Saturation adjustment. Range: `0.0` (greyscale) to `~2.0` (vivid). `1.0` is unchanged.
    /// Maps to `CIColorControls.inputSaturation`.
    case saturation(Double)

    /// Exposure adjustment in EV (stops). Range: `-2.0` to `2.0` covers most practical uses.
    /// Maps to `CIExposureAdjust.inputEV`.
    case exposure(Double)

    /// Sepia tone. `intensity` ranges `0.0...1.0`. Default `1.0`.
    /// Maps to `CISepiaTone.inputIntensity`.
    case sepia(intensity: Double = 1.0)

    /// Photographic black-and-white conversion via `CIPhotoEffectMono`.
    case mono

    /// 3D color lookup table loaded from a `.cube` file. Use ``Filter/lut(url:)`` for
    /// one-shot construction from a URL, or build a ``LUT`` once and reuse it across
    /// clips for cheaper composition. Maps to `CIColorCube`.
    case lut(LUT)

    /// Chroma-key (green-screen) — removes pixels matching ``ChromaKey/color`` within
    /// ``ChromaKey/threshold``. Use ``Filter/chromaKey(color:threshold:)`` for one-shot
    /// construction, or build a ``ChromaKey`` once and reuse it. Maps to `CIColorCube`
    /// with a programmatically-built cube.
    case chromaKey(ChromaKey)

    /// The underlying CIFilter name. Internal — used by ``FilterProcessor``.
    internal var ciFilterName: String {
        switch self {
        case .brightness, .contrast, .saturation: return "CIColorControls"
        case .exposure:  return "CIExposureAdjust"
        case .sepia:     return "CISepiaTone"
        case .mono:      return "CIPhotoEffectMono"
        case .lut:       return "CIColorCube"
        case .chromaKey: return "CIColorCube"
        }
    }

    /// Build a new filter case substituting `scalar` for this filter's primary numeric
    /// parameter. Filters without a primary scalar parameter (.mono, .lut, .chromaKey)
    /// ignore the value and return self. Used by the v0.8.2 filter intensity animation
    /// path — the engine samples the animation per frame and calls `withScalar(_:)`
    /// before applying.
    internal func withScalar(_ scalar: Double) -> Filter {
        switch self {
        case .brightness:  return .brightness(scalar)
        case .contrast:    return .contrast(scalar)
        case .saturation:  return .saturation(scalar)
        case .exposure:    return .exposure(scalar)
        case .sepia:       return .sepia(intensity: scalar)
        case .mono, .lut, .chromaKey: return self
        }
    }

    /// Apply this filter to a CoreImage `CIImage`.
    internal func apply(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: ciFilterName)
        filter?.setValue(image, forKey: kCIInputImageKey)
        switch self {
        case .brightness(let v):
            filter?.setValue(v, forKey: kCIInputBrightnessKey)
        case .contrast(let v):
            filter?.setValue(v, forKey: kCIInputContrastKey)
        case .saturation(let v):
            filter?.setValue(v, forKey: kCIInputSaturationKey)
        case .exposure(let ev):
            filter?.setValue(ev, forKey: kCIInputEVKey)
        case .sepia(let intensity):
            filter?.setValue(intensity, forKey: kCIInputIntensityKey)
        case .mono:
            break  // no parameters
        case .lut(let lut):
            filter?.setValue(lut.dimension, forKey: "inputCubeDimension")
            filter?.setValue(lut.data, forKey: "inputCubeData")
        case .chromaKey(let key):
            filter?.setValue(ChromaKey.cubeDimension, forKey: "inputCubeDimension")
            filter?.setValue(key.cubeData, forKey: "inputCubeData")
        }
        return filter?.outputImage ?? image
    }
}

public extension Filter {
    /// Build a `.lut` filter from a `.cube` file URL. Loads and parses the file
    /// synchronously; throws ``KadrError/invalidLUT(_:reason:)`` if the file is missing
    /// or malformed. Equivalent to `.lut(try LUT(url: url))` — provided as a
    /// convenience so call sites only need a single `try`.
    static func lut(url: URL) throws -> Filter {
        .lut(try LUT(url: url))
    }

    /// Build a `.chromaKey` filter from a target color and chroma threshold. Equivalent
    /// to `.chromaKey(ChromaKey(color: color, threshold: threshold))`. Build a
    /// ``ChromaKey`` directly if you want to share the configuration across clips
    /// (the cube is computed once at construction).
    static func chromaKey(color: PlatformColor, threshold: Double) -> Filter {
        .chromaKey(ChromaKey(color: color, threshold: threshold))
    }
}
