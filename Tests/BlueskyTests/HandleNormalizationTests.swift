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
}
