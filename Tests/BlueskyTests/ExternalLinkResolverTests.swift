import Testing
import Foundation
@testable import Bluesky

@Suite("ExternalLinkCard model")
struct ExternalLinkCardTests {

    private static let baseURL = URL(string: "https://example.com")!

    private static func baseline(
        url: URL = baseURL,
        title: String = "Title",
        description: String = "Description",
        thumbnailJPEG: Data? = nil
    ) -> ExternalLinkCard {
        ExternalLinkCard(
            url: url,
            title: title,
            description: description,
            thumbnailJPEG: thumbnailJPEG
        )
    }

    @Test
    func cardEquatableHonorsAllFields() {
        let baseline = Self.baseline()

        // Same construction yields ==.
        #expect(baseline == Self.baseline())

        // Each variant differs in exactly one field and must compare !=.
        let differentURL = Self.baseline(url: URL(string: "https://other.example")!)
        #expect(baseline != differentURL)

        let differentTitle = Self.baseline(title: "Other Title")
        #expect(baseline != differentTitle)

        let differentDescription = Self.baseline(description: "Other description")
        #expect(baseline != differentDescription)

        let differentThumbnail = Self.baseline(thumbnailJPEG: Data([0x01, 0x02]))
        #expect(baseline != differentThumbnail)
    }

    @Test
    func cardIDIsURL() {
        let url = URL(string: "https://example.com/page")!
        let card = ExternalLinkCard(
            url: url,
            title: "T",
            description: "D",
            thumbnailJPEG: nil
        )
        #expect(card.id == url)
    }
}

@Suite("MockExternalLinkResolver fixtures")
struct MockExternalLinkResolverTests {

    @Test
    func mockResolvesExampleDotComToCardWithNilThumbnail() async throws {
        let resolver = MockExternalLinkResolver()
        let card = try await resolver.resolve(url: URL(string: "https://example.com")!)
        #expect(card.title == "Example Domain")
        #expect(card.description == "Reserved for documentation.")
        #expect(card.thumbnailJPEG == nil)
    }

    @Test
    func mockResolvesAnthropicDotComToCardWithJPEGThumbnail() async throws {
        let resolver = MockExternalLinkResolver()
        let card = try await resolver.resolve(url: URL(string: "https://anthropic.com")!)
        #expect(card.title == "Anthropic")
        #expect(card.description == "AI safety company.")
        #expect(card.thumbnailJPEG != nil)
        #expect((card.thumbnailJPEG?.isEmpty ?? true) == false)
    }

    @Test
    func mockThrowsBadMetadataForBrokenURL() async {
        let resolver = MockExternalLinkResolver()
        await #expect(throws: ExternalLinkResolverError.badMetadata) {
            _ = try await resolver.resolve(url: URL(string: "https://broken.example")!)
        }
    }

    @Test
    func mockThrowsBadMetadataForUnknownURL() async {
        let resolver = MockExternalLinkResolver()
        await #expect(throws: ExternalLinkResolverError.badMetadata) {
            _ = try await resolver.resolve(url: URL(string: "https://random.example")!)
        }
    }
}
