# Square camera capture for Compose — design

**Date:** 2026-05-22
**Status:** Approved, ready for implementation plan
**Phase tag:** Phase J1 (first Phase J work item)
**Successor of:** Phase C (Compose: images via PhotosPicker)

## Problem

Compose lets users attach images only via `PhotosPicker` — pictures already in
the user's photo library. There is no path to **take a photo right now** from
inside the app, which is the canonical "I just saw this, posting from my
phone" flow on every comparable client (Bluesky's own iOS app, X, Instagram).

The Bluesky `app.bsky.embed.images` shape is aspect-agnostic, but for our v2
we want capture **composed for the post at capture time** — a 1:1 square
viewfinder so users frame for the result rather than crop later. This nudges
toward the visual identity of the app (Mantis admin restyle, square cards,
consistent 1:1 hero thumbnails) and keeps post-capture editing out of scope.

## Goals

- Add a "Take photo" affordance to Compose's Images section, inline with the
  existing `PhotosPicker`, with a `camera` SF Symbol button at the trailing
  edge of the same row.
- Capture is **live 1:1**: the viewfinder is masked top/bottom so the visible
  window is exactly square. What the user sees is exactly what's attached.
- Standard Instagram-style review screen between shutter and attach
  (Use photo / Retake).
- Reuse the existing `ComposeAttachment` shape and `ImageProcessor` JPEG
  pipeline so the downstream send path (`APIClient.createPost(images:)`,
  alt-text, 1 MB cap, exclusive-embed-slot rule) is unchanged.
- Honor portrait-only orientation while still producing correctly-oriented
  EXIF for face-up/face-down captures (use `RotationCoordinator`).
- All `AVCaptureSession` mutation off the main thread.
- Pure square-crop helper unit-tested via `swift test` on macOS, matching
  the `ImageProcessor` testability pattern from Phase C.

## Non-goals (explicit)

- **Front camera** — back camera only. Selfie flip is a clear follow-up if
  asked for; not v1.
- **Flash control** — auto-exposure is enough; no UI toggle.
- **Tap-to-focus, pinch-to-zoom, exposure compensation, grid overlay** —
  follow-ups, none load-bearing for v1.
- **HEIC capture pass-through** — we always JPEG-encode through
  `ImageProcessor` for parity with the PhotosPicker path and because
  Bluesky requires JPEG. The raw `AVCapturePhoto` is JPEG'd at capture time.
- **Video / Live Photos / burst** — out of scope. No microphone permission.
- **Capture-time editing (crop adjustment, rotation, filters)** —
  if the user wants to adjust crop, they tap Retake and reframe.
- **macOS** — the Camera module compiles under `#if os(iOS)` only;
  `swift test` on macOS still runs the pure-helper tests.
- **In-camera multi-shot** — return to Compose after one capture; user
  taps camera again to add another (up to the existing 4-image cap).
- **Reusing `UIImagePickerController`** — explicitly rejected; we own the
  capture surface so we can render the square mask and review screen.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **`AVCaptureSession` + `AVCapturePhotoOutput`** (custom UI) | Required by the live 1:1 viewfinder decision (per axiom-media: `UIImagePickerController` doesn't give arbitrary overlay control). |
| **`RotationCoordinator` (iOS 17+)** for both preview and capture rotation | App is portrait-only, but a user can hold the device face-up; without `RotationCoordinator` the captured EXIF can end up sideways. ~10 LOC overhead. The deprecated `videoOrientation` is also flagged by axiom-media. |
| **One new module: `Sources/Camera/`** | Mirrors `Sources/Compose/`, `Sources/Templates/`, `Sources/Auth/` — feature modules. Camera has no reason to live inside `Compose/` since it has zero dependency on Compose internals; Compose depends on Camera, not the other way. |
| **Pure `CenterSquareCrop.crop(_:)`** as a separate type from `ImageProcessor` | One job each. `ImageProcessor` resizes + bisects quality; `CenterSquareCrop` does geometry. Composes well: `crop → encode`. Tested independently. |
| **New `ImageProcessor.encodeJPEG(cgImage:maxBytes:)` overload** | The camera path produces a `CGImage` after cropping; re-decoding it via the existing `encodeJPEG(sourceData:)` would be wasteful. Extract the inner quality-bisect loop into this overload; the existing `sourceData:` entrypoint calls it after building the `CGImage`. No behavior change for callers of the existing API. |
| **Permission status modeled via a `CameraPermissionProvider` protocol** | Lets `CameraPermissionResolver` be unit-tested. The live impl wraps `AVCaptureDevice.authorizationStatus(for:)` + `requestAccess(for:)`. |
| **`@MainActor @Observable final class CameraSession`** | Matches `AuthService`, `TemplateApplier`, `SentSessionLog` — modern @Observable + main-isolated, with a private `DispatchQueue(label: "camera.session")` for AV configuration. |
| **`sheet(isPresented:)` from `ComposeView`, not a NavigationLink push** | Camera UI is full-screen modal by every comparable app. Sheet preserves the Compose form state underneath. |
| **No SwiftData persistence for the camera state** | `CameraSession` is per-presentation transient; reconstructed each time the sheet appears. |
| **`Log.media` logger added under `AppLogging`** | New domain, parallels `Log.storage`, `Log.auth`, etc. (existing pattern). |
| **Tests live in `Tests/CameraTests/`** | New test target. Pure tests for `CenterSquareCrop` and `CameraPermissionResolver`. `ImageProcessor` overload tests get appended to `Tests/ComposeTests/ComposeTests.swift` since the type lives in `Sources/Models/`. |
| **Privacy string: `NSCameraUsageDescription = "Take a photo to attach to your Bluesky post."`** | Concrete and user-relevant; App Store reviewers flag vague strings. |

## Architecture

### New module: `Sources/Camera/`

```
Sources/Camera/
├─ CameraSession.swift          // @MainActor @Observable wrapper around
│                               // AVCaptureSession + AVCapturePhotoOutput.
│                               // Owns sessionQueue, rotation coordinator,
│                               // and the captured-photo continuation.
├─ CameraPreviewLayer.swift     // UIViewRepresentable wrapping
│                               // AVCaptureVideoPreviewLayer (Pattern 2
│                               // in axiom-media camera-capture.md).
├─ SquareCameraView.swift       // SwiftUI sheet: viewfinder + shutter,
│                               // review (Use/Retake), denied-permission
│                               // card, hardware-unavailable card.
├─ CameraPermissionResolver.swift  // Protocol + live impl wrapping
│                                  // AVCaptureDevice.authorizationStatus
│                                  // and requestAccess. Pure injectable
│                                  // for tests.
└─ CenterSquareCrop.swift       // Pure namespace. crop(_ src: CGImage)
                                // → CGImage centered to min(w,h) square.
```

### Modified

- `Sources/Models/ImageProcessor.swift` — add `encodeJPEG(cgImage:maxBytes:)`
  overload; refactor existing `encodeJPEG(sourceData:)` to delegate to it.
  No behavioral change for existing callers.
- `Sources/AppLogging/Log.swift` — add `static let media = Logger(...)`.
- `Sources/Compose/ComposeView.swift` — in the Images section, replace
  the current single-row `PhotosPicker` with an `HStack` of
  `[PhotosPicker, Spacer(), cameraButton]`; new `@State var cameraPresented`;
  new `.sheet(isPresented: $cameraPresented) { SquareCameraView(onCapture:
  ingestCameraCapture) }`; new private method
  `ingestCameraCapture(data:width:height:)` that appends a
  `ComposeAttachment` and respects the 4-image cap.
- `Package.swift` — add `Camera` library target + product; `Compose` target
  gains `Camera` as a dependency; new `CameraTests` test target.
- `App/project.yml` — no app-level change (the App target depends on
  `BlueSkyTemplatesApp` which already transitively pulls every module).
- `App/Resources/Info.plist` — add `NSCameraUsageDescription` key.

### New tests

```
Tests/CameraTests/
├─ CenterSquareCropTests.swift            // Pure, runs on macOS via swift test.
└─ CameraPermissionResolverTests.swift    // Pure, via injected provider.

Tests/ComposeTests/ComposeTests.swift     // +ImageProcessor.encodeJPEG(cgImage:)
                                          //  suite appended.
```

## Data flow

```
ComposeView                                 SquareCameraView         CameraSession
    │                                            │                        │
    │  user taps [📷]  ─────────────────────────▶│                        │
    │  cameraPresented = true                     │  onAppear              │
    │                                            │  ─ requestPermissionAndStart() ─▶
    │                                            │                        │  status → .authorized
    │                                            │                        │  sessionQueue:
    │                                            │                        │    beginConfiguration
    │                                            │                        │    addInput(back wide)
    │                                            │                        │    addOutput(photo)
    │                                            │                        │    commitConfiguration
    │                                            │                        │    startRunning
    │                                            │   bind preview ◀───────│
    │                                            │   show square mask     │
    │                                            │                        │
    │                                            │  user taps SHUTTER     │
    │                                            │  ─ capture() ─────────▶│
    │                                            │                        │  sessionQueue:
    │                                            │                        │    apply rotation angle
    │                                            │                        │    photoOutput.capturePhoto
    │                                            │                        │  delegate (sessionQueue):
    │                                            │                        │    photo.fileDataRepresentation
    │                                            │                        │    → CGImageSource
    │                                            │                        │    → CenterSquareCrop.crop
    │                                            │                        │    → ImageProcessor
    │                                            │                        │      .encodeJPEG(cgImage:)
    │                                            │   captured(data,w,h)◀──│  hop to MainActor:
    │                                            │   show review screen   │    state = .captured(...)
    │                                            │                        │
    │                                            │  user taps USE         │
    │  ◀──── onCapture(data,w,h) ────────────────│                        │
    │  attachments.append(ComposeAttachment(...))│  dismiss sheet         │  onDisappear:
    │  cameraPresented = false                   │                        │    stopRunning
    │                                            │                        │
```

**Retake path:** review screen → tap Retake → `cameraSession.resume()`
(state flips back to `.live`); session is already running, so this is
just a UI flip.

**Cancel path:** any time the user taps Cancel (toolbar X), the sheet
dismisses without invoking `onCapture`. `onDisappear` stops the session.

## Concurrency model

- `CameraSession` is `@MainActor @Observable final class`. Public API
  (`requestPermissionAndStart()`, `capture()`, `stop()`, `resume()`) is
  main-isolated.
- A private `let sessionQueue = DispatchQueue(label: "camera.session",
  qos: .userInitiated)` owns all `AVCaptureSession` configuration and
  `startRunning() / stopRunning()` calls. `sessionQueue.async { ... }`
  is used; we never block.
- `AVCapturePhotoCaptureDelegate` methods are `nonisolated` (Apple
  contract). Inside them, we extract `photo.fileDataRepresentation()`,
  run square crop + JPEG encode synchronously on the session queue
  (these are CPU-bound, not main-actor-relevant), then hop to MainActor
  via `Task { @MainActor [weak self] in self?.state = ... }` to publish
  the result to SwiftUI.
- `Sendable`: `ComposeAttachment` is already `Sendable` (struct of
  value types). `CenterSquareCrop` is a stateless enum — `Sendable` by
  default. `CameraSession` is `@MainActor`, not `Sendable`, which is
  correct (it's UI-owned).
- Per the codebase's `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` setting,
  new types are MainActor by default; we explicitly mark nonisolated
  only the AV delegate methods.

## Permissions

### Info.plist add

```xml
<key>NSCameraUsageDescription</key>
<string>Take a photo to attach to your Bluesky post.</string>
```

### State machine (`CameraPermissionState`)

```swift
enum CameraPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied        // user said no, or restricted (parental controls etc.)
    case unavailable   // no camera device on this hardware (e.g. simulator)
}
```

### UI states inside `SquareCameraView`

- `.notDetermined` → centered `ProgressView()` while `requestAccess` is
  in flight; the system permission dialog covers the screen anyway, so
  no copy is shown underneath. Transitions to `.authorized` or
  `.denied` on resolve.
- `.authorized` → viewfinder + shutter.
- `.denied` → vertical stack: SF Symbol `camera.slash`, headline
  "Camera access is off", body "BlueSky Templates needs camera access
  to take photos.", primary button "Open Settings" linking to
  `UIApplication.openSettingsURLString`, secondary "Close".
- `.unavailable` → similar layout, copy "No camera on this device",
  Close only. This is the path the iPhone 17 simulator hits since
  AVCapture has no real device.

## Error handling

| Failure | UX | Logging |
|---|---|---|
| Info.plist missing `NSCameraUsageDescription` | App crashes at first capture call (Apple-enforced). | Caught in Task #1 build. |
| Permission `.denied` | Denied-permission card with "Open Settings". | `Log.media.info("camera access denied")` |
| No camera device available | Unavailable card. | `Log.media.info("no camera device")` |
| `AVCaptureSession` config fails (couldn't add input/output) | Inline error `Label` in the sheet's viewfinder area: "Couldn't start camera." Sheet stays open with Cancel. | `Log.media.error("session config failed")` |
| Session interruption (phone call, Split View) | Overlay banner "Camera paused"; auto-clears on `AVCaptureSessionInterruptionEnded`. | `Log.media.info("session interrupted: <reason>")` |
| `capturePhoto` delegate error | Inline error `Label` above the shutter button (matches `ComposeView.attachmentError` pattern: `Label(msg, systemImage: "exclamationmark.triangle.fill")` + `BrandColor.error`). User can re-tap shutter, which clears the message. Stays on viewfinder. | `Log.media.error("photo capture failed: \(error)")` |
| `photo.fileDataRepresentation()` returns nil | Same as above. | `Log.media.error("nil photo data representation")` |
| `ImageProcessor.encodeJPEG` throws `.cannotFit` | Same inline error pattern, on the review screen. User taps Retake or Cancel. | `Log.media.error("encode failed")` |

`try?` is never used to swallow capture-pipeline errors — every failure
either surfaces to the user (inline `Label`, banner, or sheet card) or
logs explicitly.

## Testing

### Unit tests (run via `swift test` on macOS — CI runs these today)

**`CenterSquareCropTests.swift`** (new):
- portrait input (W < H) → output dims are W×W, origin Y is centered
- landscape input (W > H) → output dims are H×H, origin X is centered
- square input → identical pixels (sanity: don't redraw if no crop needed)
- 1×1 input → 1×1 output
- even and odd dimension parity → no off-by-one
- Drawn fixture: build a CGImage in code with a known checker pattern
  and assert specific pixels of the crop result.

**`CameraPermissionResolverTests.swift`** (new):
- given provider returns `.authorized` → resolver returns `.authorized`,
  doesn't call `requestAccess`
- given provider returns `.notDetermined` and `requestAccess` answers
  `true` → resolver returns `.authorized`
- given provider returns `.notDetermined` and `requestAccess` answers
  `false` → resolver returns `.denied`
- given provider returns `.denied` → resolver returns `.denied`
- given provider returns `.restricted` → resolver returns `.denied`

**`ComposeTests` additions** (existing file):
- `ImageProcessor.encodeJPEG(cgImage:maxBytes:)` returns Data under cap
- behavior matches `encodeJPEG(sourceData:)` for the same input
- preserves dimensions for square input

### Manual verification on device (added to `docs/ui-test-backlog.md`)

- Take photo from Compose → square photo lands as a row → Send → posts
  visible on Bluesky with 1:1 aspect ratio
- Permission first-launch prompt appears
- After denying once, "Open Settings" card appears and Settings opens
- Phone call mid-capture → banner shows, dismisses on call end
- Device rotation while in camera (face-up, face-down) → captured photo
  has correct EXIF orientation
- 4-image cap interaction: take 4 photos via camera; camera button
  disables alongside PhotosPicker
- Retake from review screen returns to live viewfinder, no flicker
- Cancel from viewfinder dismisses, no attachment created

## Task breakdown (preview — full plan in `docs/plans/`)

Tasks run sequentially (shared `.build/` race per
`feedback_swift_sequential_dispatches.md`). Each dispatched as a fresh
`swift-coder` (Opus 4.7) subagent with `superpowers:test-driven-development`,
`superpowers:requesting-code-review`, and `superpowers:receiving-code-review`
loaded per the standing instruction, with `/axiom-build` context available
for environment-first diagnostics.

1. **J1.A — `CenterSquareCrop` (pure helper, TDD)**
2. **J1.B — `ImageProcessor.encodeJPEG(cgImage:)` overload (TDD, internal refactor)**
3. **J1.C — `CameraPermissionResolver` + protocol (TDD)**
4. **J1.D — `CameraSession` + `CameraPreviewLayer` (no unit tests; integration via D's own preview + manual verification)**
5. **J1.E — `SquareCameraView` (viewfinder + review + denied/unavailable cards)**
6. **J1.F — Wire into `ComposeView`: button, sheet, `ingestCameraCapture`**
7. **J1.G — Info.plist + `Log.media` + `Package.swift` + manual test plan in `docs/ui-test-backlog.md`**

Each task ends with a `requesting-code-review` → `receiving-code-review`
checkpoint before the next task starts.

## Risk notes

- **Simulator can't actually capture.** All AVFoundation paths must
  gracefully degrade on simulator (`.unavailable` card). Reviewer should
  spot-check that running J1.E in the iPhone 17 simulator doesn't crash.
- **Permission re-prompt loop.** If a user denies, then later grants via
  Settings → returns to app → must transition cleanly from `.denied` to
  `.authorized`. Handled by re-checking `authorizationStatus` in
  `.onAppear`, not just on first instantiation.
- **Memory.** A 4032×4032 capture decodes to ~65 MB at 32 bpp. Crop +
  re-encode pipeline must not hold the full source past the crop step.
  The pure helper returns a new CGImage backed by ImageIO's own buffer;
  release the source by scoping it inside the delegate method.
- **Backgrounding mid-capture.** If the app is backgrounded between
  shutter tap and delegate callback, the photo may be discarded. v1
  acceptance: just stay on viewfinder when the app returns, user
  re-shoots.

## Acceptance criteria

- ☑ "Take photo" button visible in Compose's Images section, adjacent
  to `PhotosPicker`.
- ☑ Tapping it opens a sheet with a live 1:1 viewfinder.
- ☑ Shutter → review screen → Use → image attached as a `ComposeAttachment`
  with alt-text-required parity to the PhotosPicker path.
- ☑ Existing 4-image cap and 1 MB JPEG cap enforced.
- ☑ Permission denial UX is informative and recoverable via Settings.
- ☑ All new pure code unit-tested; new tests pass under `swift test`
  on macOS (GitLab CI's existing `test` job).
- ☑ All new types compile under Swift 6.2 strict concurrency without
  warnings (`SWIFT_STRICT_CONCURRENCY: complete`).
- ☑ App builds and runs on iPhone 17 simulator (graceful unavailable
  card) and a physical device (full capture works end-to-end).

## References

- [axiom-media camera-capture.md](../../) — Pattern 1 (session setup),
  Pattern 2 (SwiftUI preview), Pattern 3 (RotationCoordinator),
  Pattern 5 (interruptions).
- [docs/plans/2026-05-21-phase-c-compose-images.md](../plans/2026-05-21-phase-c-compose-images.md) —
  PhotosPicker + ImageProcessor pattern this extends.
- [docs/architecture.md](../architecture.md) §6.1 (no ViewModel layer),
  §6.5 (feature modules own their state types), §11 step 4 cont.
  (image embed shape), §8.3 (1 MB / 4-image cap), §9.2 (reduce-motion).
