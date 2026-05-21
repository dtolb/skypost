# Phase F — External link card embed

> **Source spec:** [`docs/architecture.md`](../architecture.md) §8.3 (post path & embeds), §8.4 gap #6 ("Force-load of thumbnail in `buildExternalEmbed` via `Data(contentsOf:)` — workaround: Pre-fetch external thumbnails ourselves before calling"), §11 deferred-feature list, and §6.1 (`@Observable` + `@Environment`).
>
> **Goal:** when the user types a URL in the composer, the app detects it, fetches Open Graph metadata + thumbnail, and attaches a Bluesky `external` embed on Send. Matches the official Bluesky app's link-card UX: zero-click for the common path, with a Remove button to opt out.
>
> **Branch:** `feature/phase-f-external-link-card` off `feature/phase-e-templates-to-compose` (Phase E's MR !5 is still open; F stacks on top → future MR !6 targets !5's source branch).

## Out of scope (explicit)

- **Multiple link cards per post.** Bluesky's `app.bsky.embed` slot is exclusive: one embed per record, period. We attach at most one card (first URL in text wins).
- **Cards alongside images.** Same slot — if the user has image attachments, the card is silently suppressed. The URL still becomes a clickable facet (ATProtoKit auto-parses URL facets per §8.3), so no link functionality is lost.
- **Manually editing the fetched card** (override title, description, thumbnail). Bluesky's official app doesn't allow this either; users can Remove the card and the URL stays as a facet.
- **Link cards on Templates.** Templates carry text + hashtags only, unchanged from Phase E. Link cards are a Composer-only thing.
- **Quote posts / reply embeds.** Different embed types (`record`, `recordWithMedia`) — separate phase.
- **Caching the resolved card across composer sessions.** Each fresh composer fetches anew. The LPMetadataProvider call is fast enough (~500ms typical) that the cost-benefit doesn't favor a cache. Revisit if it ever feels slow.
- **Server-side rendering of the card preview.** Bluesky's PDS renders the card from the embed data we send. Our UI preview is a *local* render to show the user what they're about to attach.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **Auto-detect URLs on type**, debounced by 600 ms. No "Add link" button. | Matches the Bluesky app's UX (zero-friction). The user's typing rhythm naturally pauses for >600 ms at word boundaries / before sending. Explicit-button UX adds a tap each time. |
| **First URL in text wins.** No picker if multiple URLs are present. | Matches Bluesky-app behavior. Picking would need extra UI for a rare case. |
| **`LinkPresentation.LPMetadataProvider`** for OGP scraping. No third-party dep. | Apple-native, available since iOS 13. Returns `LPLinkMetadata` with title + imageProvider directly. Architecture §4 prefers native; LPMetadataProvider handles the HTML edge cases (redirects, charset, OG vs Twitter Card vs RSS) that we shouldn't re-implement. |
| **`ExternalLinkResolver` protocol** with `Live` (LPMetadataProvider-backed) + `Mock` impls; ComposeView reads via `@Environment(\.externalLinkResolver)`. | Mirrors `AuthProvider` (§7.2). Lets the future XCUITest harness inject a deterministic mock without network. Lets `#Preview` show the loaded state. |
| **Thumbnail downsized to ≤ 300×300 px** before blob upload. | Bluesky's CDN re-renders cards at small sizes (300×236 is the typical card thumb). Larger blobs waste storage and slow the post. Reuses `ImageProcessor.encodeJPEG` (needs a `maxLongerEdge` parameter — call out in F3). |
| **Image attachments take precedence over the card.** | One embed per record. If attachments are non-empty, link card is suppressed silently (no banner, no error). The URL remains a clickable facet via ATProtoKit's auto-parsing. Documented in `LinkCardRow` invisibility and in `APIClient.createPost`. |
| **Card preview UI:** compact row below the editor, never blocking the text field. | Mirrors the AttachmentRow layout. Loading/error states render in-place so the user knows something is happening. |
| **`.task(id: detectedURL)`** for the fetch — task cancellation comes for free when the URL changes. | iOS 26 idiom (§6.1). `Task.sleep(for: .milliseconds(600))` inside the task body provides the debounce; SwiftUI cancels the prior task automatically. |
| **Fallback title = `url.host ?? "Link"`** if metadata returns nothing. Fallback description = `url.absoluteString`. | Bluesky's `app.bsky.embed.external` requires title + description as strings — empty isn't valid. Sensible defaults beat refusing to attach. |
| **Resolver timeout: 10 s.** Past that, `.failed` state. | A composer that hangs on a slow site is worse UX than no card. 10 s covers >99 % of OGP-scrapable sites; the rest the user can re-paste. |
| **Land everything on Phase E's branch (stacked MR).** | Phase E !5 is still open; merging E before F is Dan's decision. Either way the stacked workflow doesn't change. |

## Task breakdown

Six tasks. Each dispatched as a fresh `swift-coder` (Opus 4.7) subagent. TDD for the pure pieces (F1, F2); F3 onward is wiring + UI with manual + Sim verification.

### F1 — `URLDetector` helper + tests (Compose module)

**Owns:**
- New file `Sources/Compose/URLDetector.swift`
- New tests appended to `Tests/ComposeTests/ComposeTests.swift` under a `@Suite("URLDetector")` struct

**Implementation:**

```swift
// Sources/Compose/URLDetector.swift
import Foundation

/// Finds the first URL in composer text using NSDataDetector — the same
/// machinery iOS uses for Messages / Mail link autodetection, so the
/// edge cases (trailing punctuation, schemeless hosts, IDN, fragments)
/// already work the way users expect.
///
/// Caseless enum so callers can't accidentally instantiate it.
public enum URLDetector {

    private static let detector: NSDataDetector = {
        // NSTextCheckingResult.CheckingType is a OptionSet — `.link` selects URL detection.
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    public static func firstURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range)
            .lazy
            .compactMap(\.url)
            .first
    }
}
```

**Tests (Swift Testing — `@Suite("URLDetector")`):**

1. `emptyTextReturnsNil`
2. `textWithoutURLReturnsNil` — e.g. `"hello world"`
3. `bareURLReturnsURL` — `"https://anthropic.com"` → `URL(string: "https://anthropic.com")`
4. `schemelessHostReturnsURL` — `"check out anthropic.com today"` → URL with scheme normalized by NSDataDetector
5. `multipleURLsReturnsFirst` — `"see https://a.com and https://b.com"` → URL for `a.com`
6. `URLAdjacentToPunctuationReturnsTrimmedURL` — `"visit https://a.com."` → URL without the trailing period

**Verification gates:**
- `swift build` clean.
- `swift test` — `71 tests in 13 suites passed` (65 prior + 6 new).
- No `xcodebuild` (no UI yet).

**Commit:** `feat(compose): URLDetector via NSDataDetector for link cards`

### F2 — `ExternalLinkCard` model + `ExternalLinkResolver` protocol + `MockExternalLinkResolver` + tests (Bluesky module)

**Owns:**
- New files `Sources/Bluesky/ExternalLinkCard.swift`, `Sources/Bluesky/ExternalLinkResolver.swift`, `Sources/Bluesky/MockExternalLinkResolver.swift`
- New tests in `Tests/BlueskyTests/ExternalLinkResolverTests.swift`

**Implementation:**

```swift
// Sources/Bluesky/ExternalLinkCard.swift
import Foundation

/// What the composer eventually attaches as a Bluesky `external` embed.
/// `thumbnailJPEG` is optional because some sites have no OG image, and
/// Bluesky accepts the embed without a `thumb` ref.
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
```

```swift
// Sources/Bluesky/ExternalLinkResolver.swift
import Foundation

public protocol ExternalLinkResolver: Sendable {
    /// Returns a card for the URL, or throws `.timeout`, `.badMetadata`,
    /// or `.thumbnailLoadFailed`. Implementations MUST honor task
    /// cancellation; ComposeView uses `.task(id:)` and a `.cancellationHandler`
    /// to drop work when the URL changes.
    func resolve(url: URL) async throws -> ExternalLinkCard
}

public enum ExternalLinkResolverError: Error, Sendable {
    case timeout
    case badMetadata
    case thumbnailLoadFailed
}
```

```swift
// Sources/Bluesky/MockExternalLinkResolver.swift
import Foundation

/// Canned responses for previews + UI tests. Three fixture URLs:
///   - https://example.com → simple card, no thumbnail
///   - https://anthropic.com → card with all fields + a fixture JPEG
///   - https://broken.example → throws .badMetadata
public struct MockExternalLinkResolver: ExternalLinkResolver {

    public init() {}

    public func resolve(url: URL) async throws -> ExternalLinkCard {
        switch url.absoluteString {
        case "https://example.com":
            return ExternalLinkCard(
                url: url,
                title: "Example Domain",
                description: "Reserved for documentation.",
                thumbnailJPEG: nil
            )
        case "https://anthropic.com":
            return ExternalLinkCard(
                url: url,
                title: "Anthropic",
                description: "AI safety company.",
                thumbnailJPEG: Self.fixtureJPEG
            )
        case "https://broken.example":
            throw ExternalLinkResolverError.badMetadata
        default:
            throw ExternalLinkResolverError.badMetadata
        }
    }

    private static let fixtureJPEG: Data = {
        // 1×1 JPEG — see ComposeTests' makeFixtureJPEG for the recipe.
        // … inline bytes …
    }()
}
```

**Tests (Swift Testing — `@Suite("ExternalLinkResolver mock + model")`):**

1. `cardEquatableHonorsAllFields` — vary url, title, description, thumbnailJPEG independently.
2. `cardIDIsURL` — `Identifiable.id == url`.
3. `mockResolvesExampleDotComToCardWithNilThumbnail`
4. `mockResolvesAnthropicDotComToCardWithJPEGThumbnail`
5. `mockThrowsBadMetadataForBrokenURL`
6. `mockThrowsBadMetadataForUnknownURL`

**Verification gates:**
- `swift build` clean.
- `swift test` — `77 tests in 14 suites passed` (71 + 6 new).

**Commit:** `feat(bluesky): ExternalLinkCard + Resolver protocol + Mock impl`

### F3 — `LiveExternalLinkResolver` via `LPMetadataProvider` (Bluesky module)

**Owns:**
- New file `Sources/Bluesky/LiveExternalLinkResolver.swift`
- Extend `Sources/Compose/ImageProcessor.swift` if needed to expose a `maxLongerEdge` parameter (it already exists — see existing `encodeJPEG`; verify and use)
- No tests for this task (network-dependent; covered by future UI tests)

**Implementation sketch (subagent fills in details):**

```swift
// Sources/Bluesky/LiveExternalLinkResolver.swift
#if canImport(LinkPresentation) && canImport(UIKit)
import Foundation
import LinkPresentation
import UIKit
import AppLogging

public struct LiveExternalLinkResolver: ExternalLinkResolver {

    public init() {}

    public func resolve(url: URL) async throws -> ExternalLinkCard {
        // 10s timeout via Task.sleep racing the fetch.
        let metadata = try await fetchMetadata(for: url, timeout: .seconds(10))
        let title = metadata.title ?? url.host ?? "Link"
        // LPLinkMetadata doesn't expose description directly; fall back to
        // the URL's hostname + path. Bluesky requires a description string.
        let description = (url.host ?? "") + (url.path.isEmpty ? "" : " — " + url.path)
        let thumbnailJPEG = try? await loadThumbnailJPEG(from: metadata.imageProvider)
        return ExternalLinkCard(
            url: url, title: title, description: description, thumbnailJPEG: thumbnailJPEG
        )
    }

    private func fetchMetadata(for url: URL, timeout: Duration) async throws -> LPLinkMetadata {
        try await withThrowingTaskGroup(of: LPLinkMetadata.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { c in
                    LPMetadataProvider().startFetchingMetadata(for: url) { md, err in
                        if let md { c.resume(returning: md) }
                        else { c.resume(throwing: err ?? ExternalLinkResolverError.badMetadata) }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ExternalLinkResolverError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func loadThumbnailJPEG(from provider: NSItemProvider?) async throws -> Data? {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        let image: UIImage = try await withCheckedThrowingContinuation { c in
            provider.loadObject(ofClass: UIImage.self) { obj, err in
                if let img = obj as? UIImage { c.resume(returning: img) }
                else { c.resume(throwing: err ?? ExternalLinkResolverError.thumbnailLoadFailed) }
            }
        }
        guard let pngData = image.pngData() else { return nil }
        // Downsize via ImageProcessor — already enforces ≤ 1 MB JPEG cap.
        // 300px is enough for the Bluesky card thumb (CDN re-renders).
        let encoded = try ImageProcessor.encodeJPEG(sourceData: pngData, maxLongerEdge: 300)
        return encoded.data
    }
}
#endif
```

**Note for the subagent:** `ImageProcessor.encodeJPEG` may not have a `maxLongerEdge` parameter today. Read the existing signature first; either extend it (and add a test) or use the existing default if 1600 px is already enforced. Architecture §8.3 references the 1 MB cap.

**Verification gates:**
- `swift build` clean.
- `swift test` — 77 passing (no new tests for F3 — network-dependent).
- `xcodebuild build -destination 'iPhone 17 Simulator'` succeeds (LP framework links).

**Commit:** `feat(bluesky): LiveExternalLinkResolver via LPMetadataProvider`

### F4 — `APIClient.createPost(text:external:)` + `(text:images:external:)` overloads (Bluesky module)

**Owns:**
- Extend `Sources/Bluesky/APIClient.swift`

**Concrete edits:**
1. Add overload:
   ```swift
   public func createPost(
       text: String,
       external: ExternalLinkCard,
       locale: Locale = .current
   ) async throws -> String
   ```
   Maps to ATProtoKit's `.external(...)` embed case. Pre-uploads the `thumbnailJPEG` blob if non-nil (look up `bluesky.uploadBlob` or equivalent ATProtoKit API; sketch in plan but subagent finds the exact name).
2. Extend `createPost(text:images:locale:)` with an optional `external: ExternalLinkCard? = nil` parameter — images-and-no-external is the normal case; the parameter exists so the composer can pass both and have images-win-silently logic enforced at the boundary:
   ```swift
   public func createPost(
       text: String,
       images: [(jpegData: Data, altText: String, pixelWidth: Int, pixelHeight: Int)],
       external: ExternalLinkCard? = nil,
       locale: Locale = .current
   ) async throws -> String {
       // images win over external — Bluesky embed slot is exclusive.
       // … existing code mostly unchanged; just gate `embed:` on images.isEmpty
   }
   ```
3. Document the precedence in the doc-comment.

**Verification gates:**
- `swift build` clean.
- `swift test` — 77 passing (no new tests; covered by UI tests later).
- `xcodebuild build` succeeds.

**Commit:** `feat(bluesky): createPost external embed + images-precedence`

### F5 — ComposeView wiring + card preview UI

**Owns:**
- `Sources/Compose/ComposeView.swift`

**Concrete edits:**
1. New env read: `@Environment(\.externalLinkResolver) private var resolver: (any ExternalLinkResolver)?`. Define the env key in `Sources/Bluesky/EnvironmentKeys.swift` (it already exists per Phase B).
2. New state:
   ```swift
   enum LinkLoadState: Equatable {
       case idle, loading(URL), loaded(ExternalLinkCard), failed(URL, reason: String)
   }
   @State private var linkState: LinkLoadState = .idle
   ```
3. New computed `detectedURL: URL? { URLDetector.firstURL(in: text) }`.
4. `.task(id: detectedURL)` modifier on the Form:
   ```swift
   .task(id: detectedURL) {
       guard let url = detectedURL else { linkState = .idle; return }
       linkState = .loading(url)
       try? await Task.sleep(for: .milliseconds(600))     // debounce
       guard !Task.isCancelled, let resolver else { return }
       do {
           let card = try await resolver.resolve(url: url)
           guard !Task.isCancelled else { return }
           linkState = .loaded(card)
       } catch {
           guard !Task.isCancelled else { return }
           linkState = .failed(url, reason: "Couldn't load preview.")
       }
   }
   ```
5. New `LinkCardRow` SwiftUI view rendering the card preview (loaded state) with a Remove button that flips state back to `.idle` and tracks "user dismissed" so the same URL doesn't auto-re-attach on the next debounce tick (small `Set<URL>` of dismissed URLs in `@State`).
6. Section in the Form below the existing Images section: shows `linkState` UI (loading row, loaded card, failed row, or hidden when idle).
7. Hide the section entirely when `!attachments.isEmpty` — images win.
8. `submit()` updates: when sending, pass `linkState`'s loaded card to `APIClient.createPost(text:external:)` (or the combined `images:external:` overload).

**Verification gates:**
- `swift build` clean.
- `swift test` — 77 passing.
- `xcodebuild build` succeeds.

**Commit:** `feat(compose): link card auto-detect + preview UI`

### F6 — App composition wiring + Phase F final review + Sim verification

**Owns:**
- `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift`

**Concrete edits:**
1. `@State private var linkResolver: any ExternalLinkResolver = LiveExternalLinkResolver()`.
2. `.environment(\.externalLinkResolver, linkResolver)` on the RootView chain.
3. Dispatch the final whole-phase reviewer.
4. Sim verification:
   - Boot app, sign in (or use restored session).
   - Open Compose, type `Check out https://anthropic.com today`.
   - Wait ~700ms — card row appears with "Anthropic" title + thumbnail.
   - Tap Send. (Orchestrator asks Dan before actually sending against the real account.)
5. Update kanban + close out Phase F.

## Done when

1. All six tasks pass spec + quality review.
2. `swift build` clean, `swift test` reports 77 passing.
3. `xcodebuild build` succeeds.
4. Sim: typed URL → debounced fetch → card preview → Send (or skip-send if Dan opts out) → tab clears.
5. Carry-forward debt: any new UI-lifecycle gotchas (analog to Phase E's lazy-tab-init race) get added to the [UI test backlog](../ui-test-backlog.md) as P0 regressions.
6. Final reviewer signs off; push + open MR !6 stacked on !5.

## Coordination notes

- **Module boundary** — Bluesky owns the resolver + card model + APIClient changes. Compose only depends on Bluesky (existing dep). LP framework imports stay inside `Sources/Bluesky/LiveExternalLinkResolver.swift` so the Compose module doesn't pull LinkPresentation into its build graph.
- **Env key** — `\.externalLinkResolver` should be defined in `Sources/Bluesky/EnvironmentKeys.swift` next to `\.apiClient` so the convention is consistent.
- **Cancellation semantics** — `.task(id: detectedURL)` cancels the old task automatically when the URL changes. The 600ms debounce inside the task body ensures rapid typing doesn't flood LPMetadataProvider. Verify `Task.isCancelled` checks before each state mutation.
- **Image precedence** — enforced in BOTH UI (hide LinkCardRow when attachments non-empty) and API (the `images:external:` overload drops `external` when images is non-empty). UI hiding is the user-facing intent; API enforcement is defense in depth so a future composer can't break it.
- **Bluesky external embed required fields** — title and description must be non-empty strings. Fallbacks: title = url.host ?? "Link"; description = url.host + " " + url.path. Don't send empty strings.
- **No `print()`. No `MainActor.run`. No `.onAppear { Task { } }`.**
- **Add to the UI test backlog** when this lands: a P1 test for "URL in text + no images → card preview appears within ~1s"; a P1 test for "URL + images attached → card preview hidden"; a P2 for "URL that times out → failed banner appears within 10s".
