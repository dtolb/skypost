// ExternalLinkCard — value type for Bluesky `external` post embeds.
//
// Pre-Phase-F-F4: this is the payload the Composer hands APIClient when
// it wants to attach an Open Graph card. `thumbnailJPEG` is optional
// because not every URL has an OG image, and Bluesky's
// `app.bsky.embed.external` accepts the embed without a `thumb` blob ref.

import Foundation

/// What the composer eventually attaches as a Bluesky `external` embed.
/// `thumbnailJPEG` is optional because some sites have no OG image,
/// and Bluesky's `app.bsky.embed.external` accepts the embed without
/// a `thumb` blob ref.
///
/// Identifiable on URL so SwiftUI lists/rows can re-render cleanly
/// when the user types over the URL.
public struct ExternalLinkCard: Sendable, Equatable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let title: String
    public let description: String
    public let thumbnailJPEG: Data?

    public init(url: URL, title: String, description: String, thumbnailJPEG: Data?) {
        self.url = url
        self.title = title
        self.description = description
        self.thumbnailJPEG = thumbnailJPEG
    }
}
