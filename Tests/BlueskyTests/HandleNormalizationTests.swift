import Testing
@testable import Bluesky

@Suite("Bluesky handle normalization")
struct HandleNormalizationTests {

    @Test
    func stripsLeadingAtWhitespaceAndLowercases() {
        #expect("  @Dtolb.bsky.social  ".bskyNormalizedHandle == "dtolb.bsky.social")
    }

    @Test
    func plainHandleIsUnchanged() {
        #expect("dtolb.bsky.social".bskyNormalizedHandle == "dtolb.bsky.social")
    }

    @Test
    func stripsMultipleLeadingAtSigns() {
        #expect("@@dtolb.bsky.social".bskyNormalizedHandle == "dtolb.bsky.social")
    }

    @Test
    func trimsTrailingNewline() {
        #expect("dtolb.bsky.social\n".bskyNormalizedHandle == "dtolb.bsky.social")
    }

    @Test
    func mixedCaseLowercased() {
        #expect("DTOLB.BSKY.SOCIAL".bskyNormalizedHandle == "dtolb.bsky.social")
    }

    // MARK: - Edge cases

    @Test
    func emptyStringIsEmpty() {
        #expect("".bskyNormalizedHandle == "")
    }

    @Test
    func singleAtSignIsEmpty() {
        // A bare `@` is not a handle. Normalization strips it and we're
        // left with an empty string; LoginView's canSubmit gate will
        // refuse to submit. We pin this so a future "fix" to `dropFirst`
        // can't accidentally re-introduce a leading `@` here.
        #expect("@".bskyNormalizedHandle == "")
    }

    @Test
    func multipleAtSignsOnlyIsEmpty() {
        #expect("@@@".bskyNormalizedHandle == "")
    }

    @Test
    func whitespaceOnlyIsEmpty() {
        #expect("   \t\n".bskyNormalizedHandle == "")
    }

    @Test
    func unicodeContentPreservedAfterLowercase() {
        // Pin current behavior — we don't try to redefine what a Bluesky
        // handle should be at the normalization layer; the PDS rejects
        // anything it doesn't like. A user-typed handle with combining
        // diacritics survives, lowercased, with the leading @ stripped.
        let input = "@Café.bsky.social"
        #expect(input.bskyNormalizedHandle == "café.bsky.social")
    }
}
