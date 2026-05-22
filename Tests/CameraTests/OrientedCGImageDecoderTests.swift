import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Camera

@Suite("OrientedCGImageDecoder")
struct OrientedCGImageDecoderTests {

    @Test
    func rightOrientationRotatesDecodedDimensions() throws {
        let source = try makeFixtureCGImage(width: 2, height: 1)
        let data = try jpegData(from: source, orientation: 6)

        let decoded = try #require(OrientedCGImageDecoder.decode(data))

        #expect(decoded.width == 1)
        #expect(decoded.height == 2)
    }

    @Test
    func normalOrientationKeepsDecodedDimensions() throws {
        let source = try makeFixtureCGImage(width: 3, height: 2)
        let data = try jpegData(from: source, orientation: 1)

        let decoded = try #require(OrientedCGImageDecoder.decode(data))

        #expect(decoded.width == 3)
        #expect(decoded.height == 2)
    }
}

private func makeFixtureCGImage(width: Int, height: Int) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw FixtureError.contextCreationFailed
    }

    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else {
        throw FixtureError.imageMakeFailed
    }
    return image
}

private func jpegData(from image: CGImage, orientation: Int) throws -> Data {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
        throw FixtureError.destinationCreationFailed
    }

    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: orientation,
        kCGImageDestinationLossyCompressionQuality: 0.95,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw FixtureError.destinationFinalizeFailed
    }
    return output as Data
}

private enum FixtureError: Error {
    case contextCreationFailed
    case imageMakeFailed
    case destinationCreationFailed
    case destinationFinalizeFailed
}
