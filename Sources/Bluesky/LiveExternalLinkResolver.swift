// LiveExternalLinkResolver — production OG-card resolver via Apple's
// LPMetadataProvider, with a 10s deadline race and proper task-
// cancellation propagation.
//
// Wrapped in `#if canImport(LinkPresentation) && canImport(UIKit)` so the
// SPM test target on macOS still compiles: LinkPresentation exists on
// macOS, but our thumbnail path is UIImage-mediated (the iOS-typical
// LPLinkMetadata.imageProvider hands us a UIImage). The composition root
// in Phase F task F6 wires this up; ComposeView calls through the
// ExternalLinkResolver protocol so previews / tests can swap in a stub.
//
// Cancellation: ComposeView drives this from `.task(id: detectedURL)` so
// when the user keeps typing past a URL we MUST drop the in-flight LP
// fetch. `withTaskCancellationHandler` forwards Task cancellation to
// `provider.cancel()`. The deadline race (`withThrowingTaskGroup` against
// `Task.sleep`) ensures we don't block past `timeout` even if LP itself
// never returns.
//
// Thumbnail handling: per ExternalLinkResolverError.thumbnailLoadFailed's
// doc, a failed thumb is non-fatal — caller still attaches the card with
// title + description. Hence `try?` on the thumbnail path.

#if canImport(LinkPresentation) && canImport(UIKit)
import Foundation
// `@preconcurrency` is required on iOS SDK 26: LinkPresentation's
// LPLinkMetadata / LPMetadataProvider / NSItemProvider haven't been
// audited for Swift 6 Sendable conformance, so under strict-concurrency
// the bare import flags them as non-Sendable when they cross our task
// group boundary. The types are de facto safe to hop tasks (LP is a
// read-only metadata payload; we don't share the provider across tasks);
// `@preconcurrency` downgrades the errors to warnings until Apple
// annotates the framework.
@preconcurrency import LinkPresentation
import UIKit
import AppLogging
import Models

public struct LiveExternalLinkResolver: ExternalLinkResolver {

    private let timeout: Duration

    public init(timeout: Duration = .seconds(10)) {
        self.timeout = timeout
    }

    public func resolve(url: URL) async throws -> ExternalLinkCard {
        Log.network.info("Resolving OG card host=\(url.host ?? "?", privacy: .public)")
        let metadata = try await fetchMetadata(for: url)
        // LPLinkMetadata.title is documented as String? but the framework
        // does not promise non-empty when present; an empty title here
        // would render as a blank-looking card. Trim + nil-coalesce so we
        // fall through to the host / "Link" instead.
        let candidateTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (candidateTitle?.isEmpty == false ? candidateTitle : nil) ?? url.host ?? "Link"
        let description = Self.fallbackDescription(for: url)
        // Per .thumbnailLoadFailed's WHY: a missing thumb is recoverable;
        // we still want to attach a card with title + description.
        let thumbnailJPEG = try? await loadThumbnailJPEG(from: metadata.imageProvider)
        return ExternalLinkCard(
            url: url,
            title: title,
            description: description,
            thumbnailJPEG: thumbnailJPEG
        )
    }

    // MARK: - LPMetadataProvider

    /// Races the LP fetch against a `Task.sleep(timeout)`. Whichever task
    /// finishes first wins; the other is cancelled via `group.cancelAll()`.
    /// `withTaskCancellationHandler` propagates structural cancellation
    /// from ComposeView's `.task(id:)` into `provider.cancel()`.
    private func fetchMetadata(for url: URL) async throws -> LPLinkMetadata {
        do {
            return try await withThrowingTaskGroup(of: LPLinkMetadata.self) { group in
                let provider = LPMetadataProvider()
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            provider.startFetchingMetadata(for: url) { metadata, error in
                                if let metadata {
                                    continuation.resume(returning: metadata)
                                } else {
                                    continuation.resume(
                                        throwing: error ?? ExternalLinkResolverError.badMetadata
                                    )
                                }
                            }
                        }
                    } onCancel: {
                        provider.cancel()
                    }
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ExternalLinkResolverError.timeout
                }
                // `group.next()` only returns nil when the group is empty;
                // we added two tasks above, so nil is unreachable. Crash
                // rather than silently swallowing the bug as .badMetadata.
                guard let winner = try await group.next() else {
                    fatalError("LiveExternalLinkResolver: TaskGroup empty after addTask")
                }
                group.cancelAll()
                return winner
            }
        } catch ExternalLinkResolverError.timeout {
            // Not an error per se — slow URLs are worth surfacing in
            // production logs so we can correlate user reports against
            // specific hosts without scraping the failure logs.
            Log.network.notice("OG card fetch timed out host=\(url.host ?? "?", privacy: .public)")
            throw ExternalLinkResolverError.timeout
        } catch {
            Log.network.error("OG card metadata fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Thumbnail

    /// LP hands us an `NSItemProvider` that may load as a `UIImage`. We
    /// convert UIImage → PNG → JPEG-downsized-to-300px via the shared
    /// ImageProcessor (lives in Models; same encoder the composer uses).
    /// PNG as the intermediate is a deliberate choice over CGImage round-
    /// tripping: NSItemProvider's UIImage loader already produces a fully
    /// decoded bitmap, so re-encoding to PNG once and feeding ImageIO is
    /// simpler than poking at the underlying CGImage when LP could just as
    /// well return a UIImage backed by an HDR/animated source.
    private func loadThumbnailJPEG(from provider: NSItemProvider?) async throws -> Data {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else {
            throw ExternalLinkResolverError.thumbnailLoadFailed
        }
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: error ?? ExternalLinkResolverError.thumbnailLoadFailed
                    )
                }
            }
        }
        guard let pngData = image.pngData() else {
            throw ExternalLinkResolverError.thumbnailLoadFailed
        }
        let encoded = try ImageProcessor.encodeJPEG(sourceData: pngData, maxLongerEdge: 300)
        return encoded.data
    }

    // MARK: - Fallback description

    /// Bluesky's `app.bsky.embed.external` schema requires a non-empty
    /// `description`. LPLinkMetadata doesn't expose one (its public API
    /// surface is title + image + URL), so we synthesize from the URL
    /// itself. Host + path is friendlier than the raw absolute string
    /// because it elides scheme + query, which lets the card preview
    /// show "anthropic.com/news/whatever" instead of a 200-char query soup.
    static func fallbackDescription(for url: URL) -> String {
        let host = url.host ?? ""
        let path = url.path(percentEncoded: false)
        if !path.isEmpty && path != "/" {
            return "\(host)\(path)"
        }
        return host.isEmpty ? url.absoluteString : host
    }
}

#endif
