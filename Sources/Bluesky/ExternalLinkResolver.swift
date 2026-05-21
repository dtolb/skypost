import Foundation

/// Resolves a URL into an OG-card payload. Implementations MUST honor
/// Swift task cancellation; ComposeView's `.task(id: detectedURL)`
/// drops in-flight work as soon as the URL changes.
public protocol ExternalLinkResolver: Sendable {
    func resolve(url: URL) async throws -> ExternalLinkCard
}

public enum ExternalLinkResolverError: Error, Sendable {
    case timeout
    case badMetadata
    case thumbnailLoadFailed
}
