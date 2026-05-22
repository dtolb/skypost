import Foundation
import CoreGraphics
import ImageIO

enum OrientedCGImageDecoder {

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let maxPixelSize = sourcePixelSize(source).map { max($0.width, $0.height) }

        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]

            if let orientedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return orientedImage
            }
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func sourcePixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }

        return (width, height)
    }
}
