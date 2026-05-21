// ExternalLinkResolver — protocol + error surface for OG-card fetching.
//
// Pre-Phase-F-F3: the live impl will wrap LPMetadataProvider behind a
// timeout. ComposeView drives this from `.task(id: detectedURL)`, so
// every impl MUST honor task cancellation.

import Foundation

/// Resolves a URL into an OG-card payload. Implementations MUST honor
/// Swift task cancellation; ComposeView's `.task(id: detectedURL)`
/// drops in-flight work as soon as the URL changes.
public protocol ExternalLinkResolver: Sendable {
    func resolve(url: URL) async throws -> ExternalLinkCard
}

public enum ExternalLinkResolverError: Error, Sendable {
    /// Fetcher exceeded its deadline. Caller should drop the card but
    /// keep the URL as a facet so it's still clickable; user can re-paste
    /// to retry.
    case timeout
    /// LPMetadataProvider returned nothing usable (no title, no
    /// description, or the URL didn't resolve). Caller drops the card;
    /// URL stays as a facet so the link remains clickable in the post.
    case badMetadata
    /// Metadata fetched OK but the thumbnail image load failed (network,
    /// decoder error, or non-image MIME type). Caller still attaches the
    /// card with title + description — just without a thumb.
    case thumbnailLoadFailed
}
