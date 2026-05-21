# Phase C — Compose: images

> **Source spec:** [`docs/architecture.md`](../architecture.md) §11 step 4 cont., §8.3 (post path: image embed shape, `ATProtoTools.ImageQuery` fields, ≤1 MB JPEG per image, 4-image cap), §2 (v1 audit's image bugs we're explicitly avoiding).
>
> **Goal:** Attach up to 4 images to a Compose post, with per-image alt text and correct aspect ratio. Branch stacks on `feature/compose-text`; opens a third MR after merge.
>
> **Branch:** `feature/compose-images` off `feature/compose-text`.

## Out of scope (explicit)

- **Video / GIF / external link cards / quote embeds** — Bluesky supports them; we don't ship them in v2 yet.
- **iCloud Photos remote-asset fetch fallbacks** — `PhotosPicker` returns a `PhotosPickerItem` that we load via `loadTransferable(type: Data.self)`; iCloud round-trips are slow but transparent. No UI for "this image needs to download" spinner in Phase C.
- **Image editing** — no crop, no rotate, no filter. The image goes through as-shot (just resized + JPEG-encoded for upload).
- **HEIC pass-through** — Bluesky requires JPEG. We always re-encode to JPEG even if the source was already JPEG (simpler than maybe-skip-encode logic; the cost is minor).
- **macOS attach UI** — `PhotosPicker` is iOS-only. macOS builds of the package compile but the attach affordance is hidden behind `#if os(iOS)`. Tests still run on macOS.
- **Drag-and-drop / paste from clipboard** — Phase D nicety.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **ImageIO (`CGImageSource` / `CGImageDestination`)**, not UIKit `UIGraphicsImageRenderer` | Cross-platform (iOS + macOS, no `#if canImport(UIKit)` in the helper) so the resize/encode logic is unit-testable from `swift test` on macOS. The v1 audit specifically flagged the deprecated `UIGraphicsBeginImageContextWithOptions`; this avoids both that and the modern UIKit replacement. |
| **Iterative quality bisection** to hit the 1 MB cap | Encode at quality 0.85; if over 1 MB, halve quality down to a 0.30 floor; if still over, halve dimensions (longer edge from 2048 → 1024 → 512) and retry. Predictable, no third-party deps, fits in ~60 lines. |
| **Required alt text per image** — Send disabled until every attached image has non-blank alt | UX nicety + accessibility win. v1 hard-coded "Image uploaded from BlueSkyTemplates app" on every upload (architecture §2); making alt explicit is the right correction. |
| **Cap shown in UI as `n/4` next to the picker** | Mirrors the `n/300` text counter; consistent rhythm. |
| **Aspect ratio captured from the resized image's pixel dims**, not the original | The SDK needs the aspect of what was actually uploaded. Resized dims are correct. |
| **No `ImageProcessor.preview()` fixture helper exported from Sources/** | If tests need a fixture image, they generate one inline via `CGContext.draw(...)`. Production code never needs a placeholder image. |
| **Skip an `Attachment` SwiftData model** | Drafts aren't persisted in Phase C either; attachments live in `@State` on `ComposeView`. SwiftData-backed drafts are a Phase D/E item if ever. |

## Task breakdown

Tasks run sequentially (shared `.build/` race). Each dispatched as a fresh `swift-coder` (Opus 4.7) subagent with the `superpowers:test-driven-development`, `superpowers:requesting-code-review`, and `superpowers:receiving-code-review` skills loaded per the user's standing instruction.

### C1 — `ImageProcessor` (pure ImageIO resize + JPEG-encode helper)
**Owns:** new `Sources/Compose/ImageProcessor.swift`, new tests appended to `Tests/ComposeTests/ComposeTests.swift`.

- `public struct ImageProcessor` (namespace) with one method:

  ```swift
  public static func encodeJPEG(
      sourceData: Data,
      maxBytes: Int = 1_000_000,
      maxLongerEdge: Int = 2048
  ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int)
  ```

  Algorithm (architecture-spec-aligned):
  1. Make a `CGImageSource` from `sourceData`; pull `kCGImagePropertyPixelWidth` / `Height`.
  2. If longer edge > `maxLongerEdge`, downsample via `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = maxLongerEdge` and `kCGImageSourceCreateThumbnailFromImageAlways = true`.
  3. Encode to JPEG via `CGImageDestination` with `kCGImageDestinationLossyCompressionQuality` starting at 0.85.
  4. If output bytes > `maxBytes`, halve quality down to 0.30; if still over, halve `maxLongerEdge` (2048 → 1024 → 512 → 256 floor) and recurse once per shrink.
  5. Return final `Data` + final pixel dims. Throw `ImageProcessorError.cannotDecodeSource`, `.cannotEncodeJPEG`, or `.cannotFit(maxBytes:)` if all shrinks still exceed cap.

- `public enum ImageProcessorError: Error, Equatable { case cannotDecodeSource; case cannotEncodeJPEG; case cannotFit(maxBytes: Int) }`.

- **Imports:** `Foundation`, `ImageIO`, `CoreGraphics`. NO `UIKit` / `AppKit` — keep cross-platform.

- **Tests** (TDD, fail first):

  Helpers in the test file: generate a synthetic JPEG via `CGContext` + `CGImageDestination` at a known size; produce both a small (< 1 MB at default settings) and a large (~5 MB by virtue of being 4000×4000 random noise) fixture.

  1. `tinyImageReturnsUnchangedDimensions` — 800×600 fixture, default args, output dims still 800×600.
  2. `tallImageGetsDownsampledToMaxLongerEdge` — 4000×500 fixture, default args, output longer edge ≤ 2048.
  3. `largeImageStaysUnderOneMegabyteAfterEncode` — 4000×4000 noise fixture, default args, `output.data.count ≤ 1_000_000`.
  4. `respectCustomMaxBytesArgument` — same noise fixture with `maxBytes: 500_000`, output ≤ 500 KB.
  5. `garbageInputThrowsCannotDecode` — `Data(repeating: 0xFF, count: 64)` → `.cannotDecodeSource`.
  6. `aspectRatioPreservedAfterDownsample` — 3000×1500 fixture, default args, output dims ratio within 1 % of 2:1.

  These run on macOS via `swift test` (ImageIO + CoreGraphics are cross-platform). No UIKit, no iOS Simulator needed.

### C2 — `ComposeAttachment` + validation helpers
**Owns:** new `Sources/Compose/ComposeAttachment.swift`, more tests in `Tests/ComposeTests/ComposeTests.swift`.

- `public struct ComposeAttachment: Identifiable, Equatable, Sendable`:

  ```swift
  public let id: UUID
  public let jpegData: Data
  public let pixelWidth: Int
  public let pixelHeight: Int
  public var altText: String

  public init(jpegData: Data, pixelWidth: Int, pixelHeight: Int, altText: String = "")
  ```

  `altText` is `var` so the editor binds a `TextField` to it. `jpegData` and the dims are `let` (immutable post-encode).

- Extend `ComposeText`:

  ```swift
  public static let attachmentLimit: Int = 4

  public static func canAttach(currentCount: Int) -> Bool {
      currentCount < attachmentLimit
  }

  /// Send-eligibility extension: text validation per B1, AND
  /// every attachment must have non-blank alt text.
  public static func isSubmittable(
      text: String,
      attachments: [ComposeAttachment]
  ) -> Bool {
      isSubmittable(text) &&
      attachments.count <= attachmentLimit &&
      attachments.allSatisfy { !$0.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
  ```

  The single-arg `isSubmittable(_ text:)` from B1 stays in place; the new overload doesn't break callers. Note: an empty attachment list with non-empty text is still submittable (text-only posts continue to work).

- **Tests** (TDD):

  7. `canAttachAtZero` — true.
  8. `canAttachAtThree` — true.
  9. `canAttachAtFourReturnsFalse` — false.
  10. `submittableWithTextAndNoAttachments` — `isSubmittable(text: "hi", attachments: [])` → true (text-only still works).
  11. `submittableRequiresAltOnEveryAttachment` — one attachment with empty alt → false. Same attachment with alt set → true.
  12. `submittableRejectsOverAttachmentLimit` — 5 attachments → false even if text + alts are OK.

  Synthetic `ComposeAttachment` fixture: use a 1×1 JPEG generated via `ImageProcessor.encodeJPEG` against a tiny `CGContext` (just enough bytes to satisfy the struct).

### C3 — `APIClient.createPost(text:images:locale:)` + ComposeView wiring
**Owns:** `Sources/Bluesky/APIClient.swift` (additive — new overload), `Sources/Compose/ComposeView.swift` (UI additions for picker + thumbnails + alt text).

- **APIClient new overload** (do NOT remove B1's `createPost(text:locale:)`; keep both, with the new one delegating to the SDK with images):

  ```swift
  public func createPost(
      text: String,
      images: [(jpegData: Data, altText: String, pixelWidth: Int, pixelHeight: Int)],
      locale: Locale = .current
  ) async throws -> String {
      guard let bluesky else { throw APIError.notAuthenticated }
      let queries = images.map { img in
          ATProtoTools.ImageQuery(
              imageData: img.jpegData,
              fileName: "image_\(UUID().uuidString).jpg",
              altText: img.altText,
              aspectRatio: .init(width: img.pixelWidth, height: img.pixelHeight)
          )
      }
      do {
          let ref = try await bluesky.createPostRecord(
              text: text,
              locales: [locale],
              embed: queries.isEmpty ? nil : .images(images: queries),
              creationDate: Date()
          )
          Log.network.info("Posted record with \(images.count, privacy: .public) image(s) uri=\(ref.recordURI, privacy: .public)")
          return ref.recordURI
      } catch {
          Log.network.error("createPostRecord(images) failed: \(error.localizedDescription, privacy: .public)")
          throw APIError.postFailed(reason: error.localizedDescription)
      }
  }
  ```

  When `images` is empty, behavior matches the text-only path — and we pass `embed: nil` so the SDK doesn't build an empty embed.

  **No tests** for the network method (mirrors existing pattern).

- **ComposeView additions** (`Sources/Compose/ComposeView.swift`):
  - `@State private var attachments: [ComposeAttachment] = []`
  - `@State private var picker: [PhotosPickerItem] = []` (iOS-only; gate with `#if os(iOS)`)
  - Section between counter and Send button:
    - `PhotosPicker("Add image", selection: $picker, maxSelectionCount: ComposeText.attachmentLimit - attachments.count, matching: .images)` — iOS-only branch.
    - `LabeledContent("Images") { Text("\(attachments.count)/\(ComposeText.attachmentLimit)") }`.
    - `ForEach(attachments) { attachment in ... }` rendering a thumbnail (`Image(uiImage: UIImage(data: attachment.jpegData)!).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(...)`) + a multi-line `TextField("Alt text (required)", text: $attachments[index].altText, axis: .vertical)` + a "Remove" button.
  - On picker change (`.onChange(of: picker)`): for each new item, `await item.loadTransferable(type: Data.self)`, run through `ImageProcessor.encodeJPEG`, append to `attachments`. Surface processor errors via the existing `SendState.failed(message:)` path or a new `attachmentError: String?` @State.
  - `canSend` recomputed: `api != nil && ComposeText.isSubmittable(text: text, attachments: attachments) && !isSending`.
  - `submit()` passes `attachments` to `api.createPost(text:images:)`. On success, also clear `attachments` after the 2-second auto-reset.
  - macOS branch: no picker; the user can still post text-only.

- **Imports added to ComposeView:** `PhotosUI` (iOS-only via `#if canImport(PhotosUI)` for compile-time safety) and `UIKit` (iOS-only, for `UIImage(data:)` thumbnail render).

- **No new tests for the view body** (architecture §4).

## Done when

1. All three tasks pass spec + quality review.
2. `swift build` + `swift test` green, zero warnings. Test count goes 40 → 52 (12 new across C1 + C2).
3. `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17'` green.
4. Orchestrator drives a manual Simulator pass: sign in → Compose → attach 1 image → fill alt text → type "with image" → Send → URI returned → screen + attachments auto-clear.
5. PR opened to `main` (orchestrator confirms with user).

## Coordination notes

- **Module boundary**: only `Bluesky` imports `ATProtoKit`. `ImageProcessor` and `ComposeAttachment` stay in `Compose`. The `(jpegData, altText, pixelWidth, pixelHeight)` tuple in the new APIClient overload is a `Sendable` value tuple, no cross-module type leakage.
- **Logging** in the image path: log image *count* (public) and final URI (public). Don't log image bytes or alt-text content — even at `.private(mask: .hash)` it's pointless.
- **No `print()`**.
- **iOS 26 idioms**: `PhotosPicker(selection: $items, maxSelectionCount:, matching: .images)`, `.onChange(of:)` two-arg closure, `.task(id:)`, `ImageIO`'s thumbnail flag.
- **Tests** stay in `Tests/ComposeTests/ComposeTests.swift` — keep the file under ~250 lines; split into multiple test files if it bloats past that.
