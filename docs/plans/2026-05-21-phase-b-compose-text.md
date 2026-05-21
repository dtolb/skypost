# Phase B — Compose (text-only)

> **Source spec:** [`docs/architecture.md`](../architecture.md) §11 step 4 ("Compose"), §8.3 (post path: createPostRecord auto-facets).
>
> **Goal:** Ship the text-only composer end-to-end: type a post, see a 300-grapheme counter, tap Send, post lands on Bluesky via ATProtoKit (facets auto-parsed). Replace the Hello tab with the Compose tab in `SignedInView`.
>
> **Branch:** `feature/compose-text` off `feature/templates-crud` (Phase A is still pre-merge at orchestrator's request — Phase B stacks on top so it can be split into separate MRs later).

## Out of scope (explicit)

- **Images / alt text / aspect ratio** — that's Phase C.
- **Template → composer integration** — Phase B.2 or Phase D. Composer for Phase B always starts blank.
- **Reply / quote / embed / external link card** — none of those for Phase B.
- **Language picker UI** — Phase B always tags the post with the user's current `Locale` (single value). A picker is Phase D polish.
- **Draft persistence** — if the user backs out mid-compose, the draft is lost. SwiftData-backed drafts can land in a later phase.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **Compose replaces Hello tab** | Hello was always a sanity check. Compose is the real feature; no reason to keep both. `postHelloWorld()` stays in `APIClient` for a phase or two as a debug surface, but the UI to invoke it goes away. |
| **Grapheme counter** uses `text.count` (Swift String == grapheme-clustered) | Matches how the user perceives length. ATProtoKit's internal truncation is UTF-8-byte based after facet parsing; perfect alignment isn't possible without re-implementing the truncation logic, so we display the simple grapheme count and disable Send at >300. |
| **Send disabled when text is blank OR > 300 graphemes** | Mirrors LoginView's `canSubmit` shape. Counter turns red when over budget. |
| **State machine: idle / sending / sent / error** | Plain `@State enum` per architecture §6.1, same pattern as `LoginView.submit()` and `HomeView.postHello`. |
| **Auto-clear text on successful send + return to idle after 2s** | UX hint that the post landed. The success toast can be polished in Phase D. |
| **No tests for the network call** | `APIClient.createPost` wraps `ATProtoBluesky.createPostRecord` which hits the network. Architecture §4: test state transitions, not view bodies — and we already don't test `APIClient.postHelloWorld`. We DO unit-test the pure validation helper. |

## Task breakdown

Tasks run sequentially (shared `.build/` race). Each dispatched as a fresh `swift-coder` (Opus 4.7) subagent.

### B1 — `APIClient.createPost(text:)` + grapheme validator
**Owns:** `Sources/Bluesky/APIClient.swift` (additive — new method, no breaking changes), `Sources/Compose/ComposeText.swift` (new — pure validation helper), `Tests/ComposeTests/ComposeTests.swift` (replace the placeholder smoke test with real coverage of the validator).

- Add to `APIClient`:
  ```swift
  public func createPost(text: String, locale: Locale = .current) async throws -> String {
      guard let bluesky else { throw APIError.notAuthenticated }
      do {
          let ref = try await bluesky.createPostRecord(
              text: text,
              locales: [locale],
              creationDate: Date()
          )
          Log.network.info("Posted record uri=\(ref.recordURI, privacy: .public)")
          return ref.recordURI
      } catch {
          Log.network.error("createPostRecord failed: \(error.localizedDescription, privacy: .public)")
          throw APIError.postFailed(reason: error.localizedDescription)
      }
  }
  ```
  Leave `postHelloWorld()` in place — Phase B.4 (or Phase D) will retire it once the new path proves out.

- New `Sources/Compose/ComposeText.swift`:
  ```swift
  import Foundation

  public enum ComposeText {
      public static let graphemeLimit: Int = 300

      /// Count graphemes the way the user perceives them.
      public static func graphemeCount(_ text: String) -> Int { text.count }

      /// Send-eligibility check. Blank-trimmed text is not eligible.
      public static func isSubmittable(_ text: String) -> Bool {
          let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return false }
          return graphemeCount(text) <= graphemeLimit
      }

      /// Remaining graphemes (negative if over budget).
      public static func remaining(_ text: String) -> Int {
          graphemeLimit - graphemeCount(text)
      }
  }
  ```

- Tests (TDD — fail first, then implement):
  1. `graphemeCountEmptyReturnsZero`
  2. `graphemeCountCountsClustersNotCodeUnits` — `"👨‍👩‍👧‍👦"` → 1 (family ZWJ cluster), `"é"` (composed) → 1, `"é"` (NFD `e + ́`) → 1.
  3. `isSubmittableRejectsBlank` — `""`, `"   "`, `"\n\n"`.
  4. `isSubmittableRejectsOverLimit` — 301 ASCII characters → false.
  5. `isSubmittableAcceptsExactly300` — 300 ASCII characters → true.
  6. `remainingIsNegativeWhenOver` — `String(repeating: "a", count: 305)` → -5.

- Delete the existing placeholder `ComposeModuleTests` (and the `ComposeFeature.moduleName == "Compose"` test). Replace with the real coverage above.

### B2 — `ComposeView` (text-only composer screen)
**Owns:** `Sources/Compose/ComposeView.swift` (new — the screen).

- `public struct ComposeView: View`.
- `@Environment(\.apiClient) private var api: APIClient?` (Compose target already depends on Bluesky per `Package.swift`).
- `@State private var text: String = ""` and `@State private var send: SendState = .idle`.
- `private enum SendState: Equatable { case idle, sending, sent(uri: String), failed(message: String) }`.
- Form / VStack layout:
  - Multi-line `TextField(_, text: $text, axis: .vertical)` with `.lineLimit(8...20)` and large font (`.body`-`.title3`-ish).
  - Counter: `Text("\(ComposeText.remaining(text))")` with `.foregroundStyle(.secondary)` when ≥ 0, `.red` when negative. Right-aligned under the editor.
  - Send button: `disabled(!canSend)` where `canSend = ComposeText.isSubmittable(text) && send != .sending`.
  - State surface row:
    - `.sent(uri)` — `Label("Posted!", systemImage: "checkmark.seal.fill")` + truncated URI; auto-clears `text` and resets `send = .idle` after 2s via `.task(id: send)`.
    - `.failed(message)` — `Label(message, systemImage: "exclamationmark.triangle.fill")`. Tap or "Try again" resets to `.idle`.
- `NavigationStack` (its own — tab-level navigation).
- `.navigationTitle("Compose")`, `#if os(iOS) .navigationBarTitleDisplayMode(.inline) #endif`.

- `send()` (private) — guards `api != nil` (graceful, NOT `fatalError` like HelloTabView does for the apiClient env value), transitions to `.sending`, awaits `api.createPost(text: text)`, transitions to `.sent(uri)` or `.failed(error.localizedDescription)`. After `.sent`, the `.task(id: send)` clears `text` and resets `send` after 2 seconds.

- `#Preview` registers a NavigationStack-wrapped ComposeView with `.environment(\.apiClient, nil as APIClient?)` (preview-only; the Send button will be disabled by the api-nil guard).

### B3 — Wire `ComposeView` into `SignedInView`; retire the Hello tab
**Owns:** `Sources/BlueSkyTemplatesApp/SignedInView.swift`, `Sources/BlueSkyTemplatesApp/HelloTabView.swift` (deletion + Sign Out relocation).

- Replace the Hello tab with a Compose tab in `SignedInView.body`:
  ```swift
  NavigationStack { ComposeView() }
      .tabItem { Label("Compose", systemImage: "square.and.pencil") }
  ```
- The Sign Out affordance lived inside HelloTabView. Move it into a small **third** tab `SettingsTabView` (new file `Sources/BlueSkyTemplatesApp/SettingsTabView.swift`) that contains:
  - Account section with Handle + DID (verbatim from HelloTabView).
  - Sign Out button (verbatim from HelloTabView).
  - Tab label: `Label("Settings", systemImage: "gearshape")`.
- Delete `Sources/BlueSkyTemplatesApp/HelloTabView.swift` after extracting its account display + Sign Out into SettingsTabView. Use `git rm` so the deletion is explicit.
- Update file header comments in `SignedInView.swift` to describe the new tab line-up (Templates / Compose / Settings).

- Imports added to `SignedInView.swift`: add `Compose` for `ComposeView`. The existing `Templates`/`Models` imports stay; remove any now-unused ones (a fresh grep should confirm).

- `BlueSkyTemplatesApp` target's dependency list in `Package.swift` already lists `Compose` — no Package.swift edit required.

## Done when

1. All three tasks pass spec + quality review.
2. `swift build` + `swift test` green, zero warnings.
3. `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17'` green.
4. Orchestrator drives a manual Simulator pass: sign in (or restore session) → Compose tab → type "hello from compose" → Send → URI returned → text clears.
5. PR opened (orchestrator coordinates with user on Phase A vs combined MR decision).

## Coordination notes

- **Module boundary**: only `Bluesky` imports `ATProtoKit`. `Compose` imports `Bluesky`/`Models`/`Auth`/`DesignSystem`/`AppLogging`/`Templates` (per `Package.swift`); use only what you need. UI calls `APIClient` via the existing `\.apiClient` environment key.
- **Logging**: posting paths can use `Log.network` from `AppLogging` — already imported in `Bluesky/APIClient.swift`.
- **No `print()`**.
- **Swift Testing** only.
- **iOS 26 idioms**: `.task(id:)`, multi-line `TextField(_, text:, axis: .vertical)`, `NavigationStack`, `@Observable` (none added in Phase B though — local state suffices).
- The `\.apiClient` env-value bridge already exists in `Sources/BlueSkyTemplatesApp/EnvironmentKeys.swift`; the implementer does not need to add a new env key.
