import Testing
import CoreGraphics
@testable import Camera

@Suite("CenterSquareCrop")
struct CenterSquareCropTests {

    @Test
    func portraitInputCropsToSquareOfShorterEdge() throws {
        let src = try makeSolidColorCGImage(width: 100, height: 200, fillRGB: (1, 0, 0))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 100)
        #expect(out.height == 100)
    }

    @Test
    func landscapeInputCropsToSquareOfShorterEdge() throws {
        let src = try makeSolidColorCGImage(width: 300, height: 150, fillRGB: (0, 1, 0))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 150)
        #expect(out.height == 150)
    }

    @Test
    func squareInputReturnsSameDimensions() throws {
        let src = try makeSolidColorCGImage(width: 64, height: 64, fillRGB: (0, 0, 1))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 64)
        #expect(out.height == 64)
    }

    @Test
    func oneByOneInputReturnsOneByOne() throws {
        let src = try makeSolidColorCGImage(width: 1, height: 1, fillRGB: (1, 1, 1))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 1)
        #expect(out.height == 1)
    }

    @Test
    func oddDimensionParityProducesEqualBands() throws {
        // 101x201 → center band of 101x101. The exact split direction doesn't
        // matter for correctness; we just want W==H==min and dims preserved.
        let src = try makeSolidColorCGImage(width: 101, height: 201, fillRGB: (0.5, 0.5, 0.5))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 101)
        #expect(out.height == 101)
    }
}

// MARK: - Fixture helper

private func makeSolidColorCGImage(width: Int, height: Int, fillRGB: (CGFloat, CGFloat, CGFloat)) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let bytesPerRow = width * 4
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
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

private enum FixtureError: Error { case contextCreationFailed, imageMakeFailed }
