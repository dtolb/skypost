import Foundation
import ImageIO
import CoreGraphics

public enum ImageProcessorError: Error, Equatable {
    case cannotDecodeSource
    case cannotEncodeJPEG
    case cannotFit(maxBytes: Int)
}

public struct ImageProcessor {

    /// Decodes `sourceData` then resize-and-encode-to-fit. Existing PhotosPicker
    /// entrypoint — behavior unchanged from Phase C.
    public static func encodeJPEG(
        sourceData: Data,
        maxBytes: Int = 1_000_000,
        maxLongerEdge: Int = 2048
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int) {

        // CGImageSourceCreateWithData returns a non-nil handle even for inputs
        // that have zero usable images (e.g. truncated downloads, container
        // formats with no decoded frame). Both modes must throw .cannotDecodeSource.
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageProcessorError.cannotDecodeSource
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let originalWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let originalHeight = props[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageProcessorError.cannotDecodeSource
        }

        let minimumLongerEdge = 256
        var currentMax = maxLongerEdge

        // Outer loop halves the longer-edge cap when even quality 0.30 can't
        // fit; floor at 256px so we can't loop forever on a pathological input.
        while currentMax >= minimumLongerEdge {
            let cgImage = try renderImage(
                from: source,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                maxLongerEdge: currentMax
            )

            if let fitted = try encodeFitting(cgImage: cgImage, maxBytes: maxBytes) {
                return fitted
            }

            currentMax /= 2
        }

        throw ImageProcessorError.cannotFit(maxBytes: maxBytes)
    }

    /// Encode-to-fit for a CGImage already at its final dimensions. Used by
    /// the Camera path which produces a cropped CGImage and doesn't need
    /// the outer `currentMax` halving loop. If the image doesn't fit at the
    /// lowest tried quality, throws `.cannotFit`.
    public static func encodeJPEG(
        cgImage: CGImage,
        maxBytes: Int = 1_000_000
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int) {
        if let fitted = try encodeFitting(cgImage: cgImage, maxBytes: maxBytes) {
            return fitted
        }
        throw ImageProcessorError.cannotFit(maxBytes: maxBytes)
    }

    // MARK: - Internals

    /// Walks the explicit quality ladder; returns the highest-fidelity-that-fits
    /// or nil if even quality 0.30 is over `maxBytes`.
    private static func encodeFitting(
        cgImage: CGImage,
        maxBytes: Int
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int)? {
        let qualities: [Double] = [0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30]
        for quality in qualities {
            let data = try encode(cgImage: cgImage, quality: quality)
            if data.count <= maxBytes {
                return (data, cgImage.width, cgImage.height)
            }
        }
        return nil
    }

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

        // Returns a CGImage scaled so its longer edge ≤ `maxLongerEdge`,
        // or the original image when it's already small enough. We use
        // `CreateThumbnailAtIndex` (rather than drawing into a CGContext)
        // because ImageIO can stream-decode at the target size, which is
        // dramatically faster on a 4000×4000 source.
        //
        // Downsample with kCGImageSourceCreateThumbnailFromImageAlways = true so
        // we always re-derive from the source (chained thumbnail-of-thumbnail
        // would accumulate quantization loss across retry shrinks).
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
