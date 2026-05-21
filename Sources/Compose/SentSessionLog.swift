// SentSessionLog — in-memory log of posts sent during the current process.
//
// Lives in `Compose` (the producer module — `ComposeView.submit()` calls
// `append(uri:body:)` on success). `HomeView` (consumer) imports `Compose`
// to read `entries`. Entries are wiped on app termination by design;
// persisting "sent posts" is largely redundant with the user's PDS feed.
//
// `@MainActor` because `@Observable` mutation must be main-bound — the
// `ComposeView.submit()` async path hops back to main before calling
// `append`, and `HomeView` reads `entries` from a SwiftUI body that's
// already main-isolated.

import Foundation
import Observation

@MainActor
@Observable
public final class SentSessionLog {

    /// A single sent-post record.
    public struct Entry: Hashable, Sendable, Identifiable {
        public let id: UUID
        /// AT-URI of the created record (e.g., `at://did:plc:.../app.bsky.feed.post/abc`).
        public let uri: String
        public let createdAt: Date
        /// First 80 characters of the post body, with newlines flattened to spaces.
        public let preview: String

        public init(id: UUID, uri: String, createdAt: Date, preview: String) {
            self.id = id
            self.uri = uri
            self.createdAt = createdAt
            self.preview = preview
        }
    }

    /// Most-recent-first list of entries. Capped at `cap`.
    public private(set) var entries: [Entry] = []

    /// Maximum entries retained; on overflow, the oldest are dropped.
    public static let cap: Int = 50

    public init() {}

    /// Appends a new entry at index 0 and trims to `cap` if needed.
    /// `now` is injectable for deterministic tests.
    public func append(uri: String, body: String, now: Date = .now) {
        let entry = Entry(
            id: UUID(),
            uri: uri,
            createdAt: now,
            preview: Self.makePreview(from: body)
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.cap {
            entries.removeLast(entries.count - Self.cap)
        }
    }

    /// Flattens newlines to spaces and truncates to 80 characters.
    /// Pure / static so the same transform can be unit-tested without
    /// constructing a log instance.
    public static func makePreview(from body: String) -> String {
        let oneLine = body.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        return String(oneLine.prefix(80))
    }
}
