import CoreGraphics

public enum CenterAspectCrop {

    public static func crop(_ source: CGImage, aspectRatio: CameraAspectRatio) -> CGImage {
        let sourceWidth = source.width
        let sourceHeight = source.height
        let sourceAspect = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let targetAspect = aspectRatio.value

        let cropWidth: Int
        let cropHeight: Int
        if abs(sourceAspect - targetAspect) < 0.001 {
            return source
        } else if sourceAspect > targetAspect {
            cropHeight = sourceHeight
            cropWidth = max(1, Int((CGFloat(cropHeight) * targetAspect).rounded(.down)))
        } else {
            cropWidth = sourceWidth
            cropHeight = max(1, Int((CGFloat(cropWidth) / targetAspect).rounded(.down)))
        }

        let originX = (sourceWidth - cropWidth) / 2
        let originY = (sourceHeight - cropHeight) / 2
        let rect = CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)

        return source.cropping(to: rect) ?? source
    }
}
