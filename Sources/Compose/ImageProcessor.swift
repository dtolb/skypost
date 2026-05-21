import Foundation
import ImageIO
import CoreGraphics

/// Errors thrown by `ImageProcessor.encodeJPEG`. Pure values (no
/// underlying-error payload) keep tests trivial to assert against.
public enum ImageProcessorError: Error, Equatable {
    case cannotDecodeSource
    case cannotEncodeJPEG
    case cannotFit(maxBytes: Int)
}

/// JPEG resize + encode for Bluesky uploads. Cross-platform (ImageIO +
/// CoreGraphics only, no UIKit/AppKit) so `swift test` can exercise the
/// resize logic on macOS without a Simulator. Avoids the v1 audit's
/// deprecated `UIGraphicsBeginImageContextWithOptions` path entirely.
public struct ImageProcessor {

    /// Downsamples (when the longer edge exceeds `maxLongerEdge`) then
    /// JPEG-encodes the input, bisecting quality and then halving
    /// dimensions until the output fits `maxBytes`. Returns the JPEG
    /// `Data` along with the final pixel dimensions so callers can
    /// populate `aspectRatio` on Bluesky image embeds.
    public static func encodeJPEG(
        sourceData: Data,
        maxBytes: Int = 1_000_000,
        maxLongerEdge: Int = 2048
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int) {

        // CGImageSourceCreateWithData returns a non-nil handle even for inputs
        // that have zero usable images (e.g. truncated downloads, container
        // formats with no decoded frame). Both modes must throw .cannotDecodeSource.
        //
        // Downsample with kCGImageSourceCreateThumbnailFromImageAlways = true so
        // we always re-derive from the source (chained thumbnail-of-thumbnail
        // would accumulate quantization loss across retry shrinks).
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageProcessorError.cannotDecodeSource
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let originalWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let originalHeight = props[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageProcessorError.cannotDecodeSource
        }

        // Outer loop halves the longer-edge cap when even quality 0.30 can't
        // fit; floor at 256px so we can't loop forever on a pathological input.
        let minimumLongerEdge = 256
        var currentMax = maxLongerEdge

        while currentMax >= minimumLongerEdge {
            let cgImage = try renderImage(
                from: source,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                maxLongerEdge: currentMax
            )

            // Highest-fidelity-that-fits wins; explicit array keeps the
            // tried quality values bit-exact across runs.
            let qualities: [Double] = [0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30]
            for quality in qualities {
                let data = try encode(cgImage: cgImage, quality: quality)
                if data.count <= maxBytes {
                    return (data, cgImage.width, cgImage.height)
                }
            }

            currentMax /= 2
        }

        throw ImageProcessorError.cannotFit(maxBytes: maxBytes)
    }

    // MARK: - Internals

    /// Returns a CGImage scaled so its longer edge ≤ `maxLongerEdge`,
    /// or the original image when it's already small enough. We use
    /// `CreateThumbnailAtIndex` (rather than drawing into a CGContext)
    /// because ImageIO can stream-decode at the target size, which is
    /// dramatically faster on a 4000×4000 source.
    private static func renderImage(
        from source: CGImageSource,
        originalWidth: Int,
        originalHeight: Int,
        maxLongerEdge: Int
    ) throws -> CGImage {
        let needsDownsample = max(originalWidth, originalHeight) > maxLongerEdge
        if !needsDownsample {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ImageProcessorError.cannotDecodeSource
            }
            return image
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongerEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessorError.cannotDecodeSource
        }
        return thumbnail
    }

    /// JPEG-encodes `cgImage` at the given lossy quality.
    private static func encode(cgImage: CGImage, quality: Double) throws -> Data {
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer, "public.jpeg" as CFString, 1, nil
        ) else {
            throw ImageProcessorError.cannotEncodeJPEG
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality as CFNumber,
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageProcessorError.cannotEncodeJPEG
        }
        return buffer as Data
    }
}
