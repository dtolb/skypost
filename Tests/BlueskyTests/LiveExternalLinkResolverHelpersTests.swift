// Tests for LiveExternalLinkResolver pure helpers. The resolver itself
// hits the network (LPMetadataProvider) so we can't test it end-to-end
// in a unit-test context — but `fallbackDescription(for:)` is pure and
// load-bearing for Bluesky's `app.bsky.embed.external.description`
// requirement, so we pin its behavior here.
//
// Wrapped in the same `#if canImport(LinkPresentation) && canImport(UIKit)`
// guard as the resolver so the macOS test build doesn't try to reference
// a symbol that doesn't exist there.

#if canImport(LinkPresentation) && canImport(UIKit)
import Testing
import Foundation
@testable import Bluesky

@Suite("LiveExternalLinkResolver helpers")
struct LiveExternalLinkResolverHelpersTests {

    @Test
    func fallbackUsesHostAndPathWhenPathIsMeaningful() {
        let url = URL(string: "https://example.com/blog/post")!
        #expect(LiveExternalLinkResolver.fallbackDescription(for: url) == "example.com/blog/post")
    }

    @Test
    func fallbackUsesHostWhenPathIsRoot() {
        let url = URL(string: "https://example.com/")!
        #expect(LiveExternalLinkResolver.fallbackDescription(for: url) == "example.com")
    }

    @Test
    func fallbackUsesAbsoluteStringWhenHostIsNil() {
        let url = URL(string: "file:///tmp/foo")!
        #expect(LiveExternalLinkResolver.fallbackDescription(for: url) == url.absoluteString)
    }
}

#endif
