import Testing
import Foundation
import ImageIO
import CoreGraphics
import Compose
import Models

@Suite("ComposeText validator")
struct ComposeTextTests {

    @Test
    func graphemeCountEmptyReturnsZero() {
        #expect(ComposeText.graphemeCount("") == 0)
    }

    @Test
    func graphemeCountCountsClustersNotCodeUnits() {
        #expect(ComposeText.graphemeCount("👨‍👩‍👧‍👦") == 1)
        #expect(ComposeText.graphemeCount("é") == 1)
        #expect(ComposeText.graphemeCount("e\u{0301}") == 1)
        #expect(ComposeText.graphemeCount("abc") == 3)
    }

    @Test
    func isSubmittableRejectsBlank() {
        #expect(ComposeText.isSubmittable("") == false)
        #expect(ComposeText.isSubmittable("   ") == false)
        #expect(ComposeText.isSubmittable("\n\n") == false)
    }

    @Test
    func isSubmittableRejectsOverLimit() {
        #expect(ComposeText.isSubmittable(String(repeating: "a", count: 301)) == false)
        // Trimmed-empty wrapper around long text — leading/trailing whitespace
        // shouldn't sneak past the blank guard, but the over-limit branch
        // should still reject in any case.
        let padded = "   " + String(repeating: "a", count: 301) + "   "
        #expect(ComposeText.isSubmittable(padded) == false)
    }

    @Test
    func isSubmittableAcceptsExactly300() {
        #expect(ComposeText.isSubmittable(String(repeating: "a", count: 300)) == true)
    }

    @Test
    func remainingIsNegativeWhenOver() {
        #expect(ComposeText.remaining(String(repeating: "a", count: 305)) == -5)
        #expect(ComposeText.remaining(String(repeating: "a", count: 300)) == 0)
        #expect(ComposeText.remaining("") == 300)
    }
}

@Suite("ComposeText template application")
struct ComposeTextTemplateApplicationTests {

    @Test
    func emptyBodyAndEmptyHashtagsReturnsEmptyString() {
        #expect(ComposeText.applyTemplate(body: "", hashtags: []) == "")
    }

    @Test
    func bodyOnlyReturnsBodyUnchanged() {
        #expect(ComposeText.applyTemplate(body: "hello", hashtags: []) == "hello")
    }

    @Test
    func hashtagsOnlyReturnsSpaceJoinedHashTokens() {
        #expect(ComposeText.applyTemplate(body: "", hashtags: ["a", "b"]) == "#a #b")
    }

    @Test
    func bodyAndHashtagsSeparatedByTwoNewlines() {
        #expect(ComposeText.applyTemplate(body: "hello", hashtags: ["a", "b"]) == "hello\n\n#a #b")
    }

    @Test
    func hashtagsArePrefixedWithHashEvenIfModelStripped() {
        #expect(ComposeText.applyTemplate(body: "x", hashtags: ["nohash"]) == "x\n\n#nohash")
    }

    @Test
    func singleHashtagWorks() {
        #expect(ComposeText.applyTemplate(body: "x", hashtags: ["only"]) == "x\n\n#only")
    }
}

@Suite("ImageProcessor JPEG resize")
struct ImageProcessorTests {

    @Test
    func tinyImageReturnsUnchangedDimensions() throws {
        let fixture = try makeFixtureJPEG(width: 800, height: 600)
        let result = try ImageProcessor.encodeJPEG(sourceData: fixture)
        #expect(result.pixelWidth == 800)
        #expect(result.pixelHeight == 600)
    }

    @Test
    func tallImageGetsDownsampledToMaxLongerEdge() throws {
        let fixture = try makeFixtureJPEG(width: 4000, height: 500)
        let result = try ImageProcessor.encodeJPEG(sourceData: fixture)
        #expect(max(result.pixelWidth, result.pixelHeight) <= 2048)
    }

    @Test
    func largeImageStaysUnderOneMegabyteAfterEncode() throws {
        let fixture = try makeFixtureJPEG(width: 4000, height: 4000)
        let result = try ImageProcessor.encodeJPEG(sourceData: fixture)
        #expect(result.data.count <= 1_000_000)
    }

    @Test
    func respectCustomMaxBytesArgument() throws {
        let fixture = try makeFixtureJPEG(width: 4000, height: 4000)
        let result = try ImageProcessor.encodeJPEG(sourceData: fixture, maxBytes: 500_000)
        #expect(result.data.count <= 500_000)
    }

    @Test
    func garbageInputThrowsCannotDecode() {
        let garbage = Data(repeating: 0xFF, count: 64)
        #expect(throws: ImageProcessorError.cannotDecodeSource) {
            _ = try ImageProcessor.encodeJPEG(sourceData: garbage)
        }
    }

    @Test
    func aspectRatioPreservedAfterDownsample() throws {
        let fixture = try makeFixtureJPEG(width: 3000, height: 1500)
        let result = try ImageProcessor.encodeJPEG(sourceData: fixture)
        let ratio = Double(result.pixelWidth) / Double(result.pixelHeight)
        #expect(abs(ratio - 2.0) <= 0.02)
    }
}

@Suite("ComposeAttachment + send eligibility")
struct ComposeAttachmentTests {

    @Test
    func canAttachAtZeroReturnsTrue() {
        #expect(ComposeText.canAttach(currentCount: 0) == true)
    }

    @Test
    func canAttachAtThreeReturnsTrue() {
        #expect(ComposeText.canAttach(currentCount: 3) == true)
    }

    @Test
    func canAttachAtFourReturnsFalse() {
        #expect(ComposeText.canAttach(currentCount: 4) == false)
    }

    @Test
    func submittableWithTextAndNoAttachments() {
        #expect(ComposeText.isSubmittable(text: "hello", attachments: []) == true)
    }

    @Test
    func submittableRequiresAltOnEveryAttachment() throws {
        let blank = try makeTinyAttachment(altText: "")
        #expect(ComposeText.isSubmittable(text: "hi", attachments: [blank]) == false)

        let described = try makeTinyAttachment(altText: "describing the photo")
        #expect(ComposeText.isSubmittable(text: "hi", attachments: [described]) == true)
    }

    @Test
    func submittableRejectsOverAttachmentLimit() throws {
        let attachments = try (0..<5).map { _ in try makeTinyAttachment(altText: "alt") }
        #expect(ComposeText.isSubmittable(text: "hi", attachments: attachments) == false)
    }
}

// MARK: - Fixtures

/// Builds a real `ComposeAttachment` backed by a 1×1 JPEG routed through
/// `ImageProcessor.encodeJPEG` — no mocks, exercises the same encode path
/// the production composer uses.
private func makeTinyAttachment(altText: String = "") throws -> ComposeAttachment {
    let fixture = try makeFixtureJPEG(width: 1, height: 1)
    let encoded = try ImageProcessor.encodeJPEG(sourceData: fixture, maxBytes: 100_000)
    return ComposeAttachment(
        jpegData: encoded.data,
        pixelWidth: encoded.pixelWidth,
        pixelHeight: encoded.pixelHeight,
        altText: altText
    )
}


/// Synthetic JPEG filled with random RGB noise so JPEG compression
/// actually does work; a flat color compresses to ~3 KB regardless of
/// dimensions and would defeat the large-image cap tests.
private func makeFixtureJPEG(width: Int, height: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw FixtureError.cannotCreateContext }

    var rng = SystemRandomNumberGenerator()
    if let buffer = ctx.data {
        let byteCount = ctx.bytesPerRow * height
        let ptr = buffer.bindMemory(to: UInt8.self, capacity: byteCount)
        for i in 0..<byteCount { ptr[i] = UInt8.random(in: 0...255, using: &rng) }
    }
    guard let cgImage = ctx.makeImage() else { throw FixtureError.cannotMakeImage }
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        output, "public.jpeg" as CFString, 1, nil
    ) else { throw FixtureError.cannotCreateDestination }
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.95 as CFNumber,
    ]
    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw FixtureError.cannotFinalize }
    return output as Data
}

private enum FixtureError: Error {
    case cannotCreateContext
    case cannotMakeImage
    case cannotCreateDestination
    case cannotFinalize
}

@Suite("URLDetector")
struct URLDetectorTests {

    @Test
    func emptyTextReturnsNil() {
        #expect(URLDetector.firstURL(in: "") == nil)
    }

    @Test
    func textWithoutURLReturnsNil() {
        #expect(URLDetector.firstURL(in: "hello world") == nil)
    }

    @Test
    func bareURLReturnsURL() {
        let url = URLDetector.firstURL(in: "https://anthropic.com")
        #expect(url != nil)
        // Round-trip via URL(string:) so we don't assume whether
        // NSDataDetector appends a trailing slash to the absoluteString.
        #expect(url == URL(string: "https://anthropic.com"))
    }

    @Test
    func schemelessHostReturnsURL() {
        let url = URLDetector.firstURL(in: "check out anthropic.com today")
        #expect(url != nil)
        #expect(url?.host == "anthropic.com")
    }

    @Test
    func multipleURLsReturnsFirst() {
        let url = URLDetector.firstURL(in: "see https://a.com and https://b.com")
        #expect(url?.host == "a.com")
    }

    @Test
    func URLAdjacentToPunctuationReturnsTrimmedURL() {
        let url = URLDetector.firstURL(in: "visit https://a.com.")
        #expect(url?.host == "a.com")
        #expect(url?.absoluteString.hasSuffix(".") == false)
    }
}
