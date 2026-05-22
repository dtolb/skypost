import CoreGraphics
import Testing
@testable import Camera

@Suite("CenterAspectCrop")
struct CenterAspectCropTests {

    @Test
    func landscapeSourceCropsToPortraitDefaultAspect() throws {
        let source = try makeSolidColorCGImage(width: 400, height: 300, fillRGB: (1, 0, 0))

        let output = CenterAspectCrop.crop(source, aspectRatio: CameraAspectRatio(width: 3, height: 4))

        #expect(output.width == 225)
        #expect(output.height == 300)
    }

    @Test
    func portraitSourceCropsToLandscapeDefaultAspect() throws {
        let source = try makeSolidColorCGImage(width: 300, height: 400, fillRGB: (0, 1, 0))

        let output = CenterAspectCrop.crop(source, aspectRatio: CameraAspectRatio(width: 4, height: 3))

        #expect(output.width == 300)
        #expect(output.height == 225)
    }

    @Test
    func matchingAspectReturnsOriginalDimensions() throws {
        let source = try makeSolidColorCGImage(width: 400, height: 300, fillRGB: (0, 0, 1))

        let output = CenterAspectCrop.crop(source, aspectRatio: CameraAspectRatio(width: 4, height: 3))

        #expect(output.width == 400)
        #expect(output.height == 300)
    }

    @Test
    func squareAspectMatchesCenterSquareCrop() throws {
        let source = try makeSolidColorCGImage(width: 320, height: 180, fillRGB: (1, 1, 1))

        let aspectOutput = CenterAspectCrop.crop(source, aspectRatio: CameraAspectRatio(width: 1, height: 1))
        let squareOutput = CenterSquareCrop.crop(source)

        #expect(aspectOutput.width == squareOutput.width)
        #expect(aspectOutput.height == squareOutput.height)
    }
}

// MARK: - Fixture helper

private func makeSolidColorCGImage(width: Int, height: Int, fillRGB: (CGFloat, CGFloat, CGFloat)) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw FixtureError.contextCreationFailed
    }
    ctx.setFillColor(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = ctx.makeImage() else {
        throw FixtureError.imageMakeFailed
    }
    return image
}

private enum FixtureError: Error {
    case contextCreationFailed
    case imageMakeFailed
}
