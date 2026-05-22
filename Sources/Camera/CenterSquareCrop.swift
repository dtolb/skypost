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
        CenterAspectCrop.crop(source, aspectRatio: CameraAspectRatio(width: 1, height: 1))
    }
}
