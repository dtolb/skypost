// CenterSquareCrop — pure CGImage → CGImage geometry helper.
//
// Center-crops an image to a square of size `min(width, height)`. No
// AVFoundation, no UIKit; cross-platform so the J1 unit tests run on
// macOS via `swift test`. Always returns a valid square — center-crop
// is well-defined for any non-empty CGImage.

import CoreGraphics

public enum CenterSquareCrop {

    /// Returns a square center-crop of `source`. When the source is already
    /// square, returns it unchanged.
    public static func crop(_ source: CGImage) -> CGImage {
        let width = source.width
        let height = source.height
        if width == height { return source }

        let side = min(width, height)
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let rect = CGRect(x: originX, y: originY, width: side, height: side)

        // CGImage.cropping returns nil only for out-of-bounds rects, which we
        // construct ourselves to fit. Force-unwrap is safe here; fall back to
        // the source defensively in case of a future CG behavior change.
        return source.cropping(to: rect) ?? source
    }
}
