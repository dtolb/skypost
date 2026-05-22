#if canImport(AppIntents)
import Testing
@testable import BlueSkyTemplatesApp

@Suite("Template app intents")
struct TemplateAppIntentsTests {

    @Test
    func blankTitleUsesFallbackTitle() {
        #expect(CreateTemplateIntent.normalizedTitle("  \n\t  ") == "Untitled Template")
    }

    @Test
    func hashtagInputUsesTemplateParserNormalization() {
        #expect(CreateTemplateIntent.normalizedHashtags("#Swift, bsky, #swift") == ["swift", "bsky"])
    }
}
#endif
