# Phase J1 — square camera capture: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Every task ends with a `superpowers:requesting-code-review` → `superpowers:receiving-code-review` checkpoint before the next task starts.

**Goal:** Add a live 1:1 viewfinder camera capture flow to Compose's Images section so users can take a square photo and attach it to a post without leaving the app, reusing the existing `ImageProcessor` + `ComposeAttachment` pipeline.

**Architecture:** New `Sources/Camera/` module. Pure cross-platform helpers (`CenterSquareCrop`, `CameraPermissionResolver` protocol) unit-tested on macOS via `swift test`. iOS-only AVFoundation surfaces (`CameraSession`, `CameraPreviewLayer`, `SquareCameraView`) gated by `#if os(iOS)`. Wired into `ComposeView` via a trailing camera button + presented sheet. Spec: [`docs/specs/2026-05-22-square-camera-capture-design.md`](../specs/2026-05-22-square-camera-capture-design.md).

**Tech Stack:** Swift 6.2 (strict concurrency, MainActor default), SwiftUI, AVFoundation (`AVCaptureSession` + `AVCapturePhotoOutput` + `AVCaptureDevice.RotationCoordinator`), ImageIO + CoreGraphics, Swift Testing.

**Sequencing rule:** Run tasks serially. Per `feedback_swift_sequential_dispatches.md`, concurrent `swift build` invocations race the shared `.build/` directory — even on disjoint files. Do not parallelize subagent dispatches.

**Branch:** Each task commits to `main` directly per this project's established cadence (see recent `git log`). No MR-per-task ceremony; review happens via the `requesting-code-review` / `receiving-code-review` cycle between tasks.

---

## File map

| Path | Status | Owner task |
|---|---|---|
| `Package.swift` | modify | J1.0, J1.E (Compose dep), J1.G |
| `Sources/Camera/CenterSquareCrop.swift` | create | J1.A |
| `Tests/CameraTests/CenterSquareCropTests.swift` | create | J1.A |
| `Sources/Models/ImageProcessor.swift` | modify | J1.B |
| `Tests/ComposeTests/ComposeTests.swift` | append | J1.B |
| `Sources/Camera/CameraPermissionResolver.swift` | create | J1.C |
| `Tests/CameraTests/CameraPermissionResolverTests.swift` | create | J1.C |
| `Sources/AppLogging/Log.swift` | modify | J1.D |
| `App/Resources/Info.plist` | modify | J1.D |
| `Sources/Camera/CameraSession.swift` | create | J1.E |
| `Sources/Camera/CameraPreviewLayer.swift` | create | J1.F |
| `Sources/Camera/SquareCameraView.swift` | create | J1.F |
| `Sources/Compose/ComposeView.swift` | modify | J1.G |
| `docs/ui-test-backlog.md` | append | J1.H |
| `kanban.md` | append | J1.H |

---

## Task J1.0 — Scaffold the Camera module

**Files:**
- Modify: `Package.swift` — add Camera target, Camera product, CameraTests test target
- Create: `Sources/Camera/CameraModule.swift` — empty placeholder so the target compiles before any real code lands
- Create: `Tests/CameraTests/CameraModuleTests.swift` — sanity test so the test target compiles

This task exists so every subsequent task can `import Camera` and `@testable import Camera` immediately without the bootstrap noise.

- [ ] **Step 1: Add Camera target + product to `Package.swift`**

In `Package.swift`, add the product line in the `products:` array (alphabetically after `Bluesky`):

```swift
.library(name: "Camera",             targets: ["Camera"]),
```

In the `targets:` array, add this target above the existing `Auth` target:

```swift
// ── Camera — AVFoundation capture surface, iOS-only at runtime. ─
// Cross-platform pure helpers (CenterSquareCrop, permission resolver)
// compile on macOS so `swift test` exercises them in CI.
.target(
    name: "Camera",
    dependencies: [
        "AppLogging",
        "Models",
    ]
),
```

In the test targets block, add:

```swift
.testTarget(
    name: "CameraTests",
    dependencies: ["Camera"]
),
```

- [ ] **Step 2: Create the empty source placeholder**

Create `Sources/Camera/CameraModule.swift`:

```swift
// Camera — square photo capture surface for Compose.
//
// Cross-platform pure helpers live alongside iOS-only AVFoundation
// types gated by `#if os(iOS)`. Spec:
// docs/specs/2026-05-22-square-camera-capture-design.md.
```

(File-level doc comment only — every subsequent task in this phase adds a real type.)

- [ ] **Step 3: Create the sanity test**

Create `Tests/CameraTests/CameraModuleTests.swift`:

```swift
import Testing
@testable import Camera

@Suite("Camera module sanity")
struct CameraModuleSanityTests {

    @Test
    func moduleImports() {
        // Trivial: if the module fails to compile, this whole file fails to build.
        // J1.A onwards replaces this with real test suites.
        #expect(true)
    }
}
```

- [ ] **Step 4: Verify build + tests pass**

Run from the repo root:

```bash
swift build
swift test --filter CameraModuleSanityTests
```

Expected: both succeed. The test reports `1 passed`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/Camera/CameraModule.swift Tests/CameraTests/CameraModuleTests.swift
git commit -m "feat(camera): scaffold Camera module (J1.0)

Empty target + sanity test so subsequent J1 tasks can import
Camera without bootstrap noise. AVFoundation surfaces land in J1.E onwards.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.A — `CenterSquareCrop` pure helper (TDD)

**Files:**
- Create: `Sources/Camera/CenterSquareCrop.swift`
- Modify: `Tests/CameraTests/CameraModuleTests.swift` — remove sanity placeholder (or keep, harmless)
- Create: `Tests/CameraTests/CenterSquareCropTests.swift`

Pure CGImage → CGImage geometry. No AVFoundation. Runs in `swift test` on macOS. Always returns a valid square (no Optional, no throws — center-crop is well-defined for any non-empty input).

- [ ] **Step 1: Write the failing test file**

Create `Tests/CameraTests/CenterSquareCropTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import Camera

@Suite("CenterSquareCrop")
struct CenterSquareCropTests {

    @Test
    func portraitInputCropsToSquareOfShorterEdge() throws {
        let src = try makeSolidColorCGImage(width: 100, height: 200, fillRGB: (1, 0, 0))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 100)
        #expect(out.height == 100)
    }

    @Test
    func landscapeInputCropsToSquareOfShorterEdge() throws {
        let src = try makeSolidColorCGImage(width: 300, height: 150, fillRGB: (0, 1, 0))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 150)
        #expect(out.height == 150)
    }

    @Test
    func squareInputReturnsSameDimensions() throws {
        let src = try makeSolidColorCGImage(width: 64, height: 64, fillRGB: (0, 0, 1))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 64)
        #expect(out.height == 64)
    }

    @Test
    func oneByOneInputReturnsOneByOne() throws {
        let src = try makeSolidColorCGImage(width: 1, height: 1, fillRGB: (1, 1, 1))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 1)
        #expect(out.height == 1)
    }

    @Test
    func oddDimensionParityProducesEqualBands() throws {
        // 101x201 → center band of 101x101, top band 50, bottom 50 (one row absorbed by integer split).
        // The exact split direction doesn't matter for correctness; we just want W==H==min and dims preserved.
        let src = try makeSolidColorCGImage(width: 101, height: 201, fillRGB: (0.5, 0.5, 0.5))
        let out = CenterSquareCrop.crop(src)
        #expect(out.width == 101)
        #expect(out.height == 101)
    }
}

// MARK: - Fixture helper

private func makeSolidColorCGImage(width: Int, height: Int, fillRGB: (CGFloat, CGFloat, CGFloat)) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let bytesPerRow = width * 4
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw FixtureError.contextCreationFailed
    }
    ctx.setFillColor(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = ctx.makeImage() else {
        throw FixtureError.imageMakeFailed
    }
    return image
}

private enum FixtureError: Error { case contextCreationFailed, imageMakeFailed }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter CenterSquareCropTests
```

Expected: build fails with `cannot find 'CenterSquareCrop' in scope`. This is the desired red-bar.

- [ ] **Step 3: Implement `CenterSquareCrop`**

Create `Sources/Camera/CenterSquareCrop.swift`:

```swift
// CenterSquareCrop — pure CGImage → CGImage geometry helper.
//
// Center-crops an image to a square of size `min(width, height)`. No
// AVFoundation, no UIKit; cross-platform so the J1 unit tests run on
// macOS via `swift test`. Always returns a valid square — center-crop
// is well-defined for any non-empty CGImage.

import CoreGraphics

public enum CenterSquareCrop {

    /// Returns a square center-crop of `source`. When the source is already
    /// square, returns it unchanged.
    public static func crop(_ source: CGImage) -> CGImage {
        let width = source.width
        let height = source.height
        if width == height { return source }

        let side = min(width, height)
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let rect = CGRect(x: originX, y: originY, width: side, height: side)

        // CGImage.cropping returns nil only for out-of-bounds rects, which we
        // construct ourselves to fit. Force-unwrap is safe here; fall back to
        // the source defensively in case of a future CG behavior change.
        return source.cropping(to: rect) ?? source
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter CenterSquareCropTests
```

Expected: `5 passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Camera/CenterSquareCrop.swift Tests/CameraTests/CenterSquareCropTests.swift
git commit -m "feat(camera): CenterSquareCrop pure helper + tests (J1.A)

Center-crop CGImage → square of min(w,h). Pure CoreGraphics, runs in
swift test on macOS. 5 cases: portrait, landscape, square (identity),
1x1 edge case, odd-dimension parity.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.B — `ImageProcessor.encodeJPEG(cgImage:)` overload (TDD)

**Files:**
- Modify: `Sources/Models/ImageProcessor.swift` — extract inner loop into new public overload, keep existing `encodeJPEG(sourceData:)` as a wrapper that calls it
- Append: `Tests/ComposeTests/ComposeTests.swift` — new test suite

Refactor without behavior change for the existing `sourceData:` entrypoint; add a CGImage-taking overload the camera path can call without re-decoding bytes.

- [ ] **Step 1: Write the failing test suite**

Append to `Tests/ComposeTests/ComposeTests.swift` (after the existing `ComposeTextTests` suite — don't reorder existing suites):

```swift
@Suite("ImageProcessor.encodeJPEG(cgImage:)")
struct ImageProcessorCGImageOverloadTests {

    @Test
    func encodesSquareCGImageUnderCap() throws {
        let img = try makeRedCGImage(side: 512)
        let result = try ImageProcessor.encodeJPEG(cgImage: img, maxBytes: 1_000_000)
        #expect(result.data.count <= 1_000_000)
        #expect(result.pixelWidth == 512)
        #expect(result.pixelHeight == 512)
    }

    @Test
    func roundTripMatchesSourceDataEntrypointForSameSquareInput() throws {
        let img = try makeRedCGImage(side: 256)
        let viaCGImage = try ImageProcessor.encodeJPEG(cgImage: img, maxBytes: 1_000_000)

        // Render the same image to PNG bytes and re-run through the existing entrypoint.
        // The two paths shrink-down identically for a 256x256 source (well under cap),
        // so both should land at quality 0.85 with matching dims.
        let pngData = try pngData(from: img)
        let viaData = try ImageProcessor.encodeJPEG(sourceData: pngData, maxBytes: 1_000_000)

        #expect(viaCGImage.pixelWidth == viaData.pixelWidth)
        #expect(viaCGImage.pixelHeight == viaData.pixelHeight)
    }

    @Test
    func tightCapTriggersQualityBisectAndStillFits() throws {
        // 1024x1024 of high-frequency noise won't fit at quality 0.85; the bisect
        // must walk down. Caller is OK getting back data slightly under cap.
        let img = try makeNoisyCGImage(side: 1024)
        let result = try ImageProcessor.encodeJPEG(cgImage: img, maxBytes: 200_000)
        #expect(result.data.count <= 200_000)
        #expect(result.pixelWidth == 1024)
        #expect(result.pixelHeight == 1024)
    }
}

// MARK: - Fixture helpers (file-scoped, reused only within this suite)

private func makeRedCGImage(side: Int) throws -> CGImage {
    try makeFilledCGImage(width: side, height: side, fillRGB: (1, 0, 0))
}

private func makeNoisyCGImage(side: Int) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let bytesPerRow = side * 4
    var bytes = [UInt8](repeating: 0, count: side * bytesPerRow)
    // Deterministic pseudo-random fill — varied enough to defeat JPEG run-length compression.
    var seed: UInt32 = 0xDEADBEEF
    for i in 0..<bytes.count {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        bytes[i] = UInt8(seed & 0xFF)
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let img = CGImage(
        width: side,
        height: side,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
    return img
}

private func makeFilledCGImage(width: Int, height: Int, fillRGB: (CGFloat, CGFloat, CGFloat)) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let bytesPerRow = width * 4
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw NSError(domain: "fixture", code: 1)
    }
    ctx.setFillColor(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = ctx.makeImage() else { throw NSError(domain: "fixture", code: 2) }
    return image
}

private func pngData(from cgImage: CGImage) throws -> Data {
    let buffer = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "fixture", code: 3)
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "fixture", code: 4) }
    return buffer as Data
}
```

The imports at the top of `Tests/ComposeTests/ComposeTests.swift` already cover `Testing`, `Foundation`, `ImageIO`, `CoreGraphics`, `Models`. If `Models` is missing, add `import Models`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ImageProcessorCGImageOverloadTests
```

Expected: build fails with `incorrect argument label 'cgImage:' in call to encodeJPEG`. Desired red-bar.

- [ ] **Step 3: Refactor `ImageProcessor.swift`**

Open `Sources/Models/ImageProcessor.swift`. Replace the existing `encodeJPEG(sourceData:maxBytes:maxLongerEdge:)` body with this: keep the outer signature and CGImageSource decode, but factor the per-currentMax loop into the new overload.

Final shape:

```swift
import Foundation
import ImageIO
import CoreGraphics

public enum ImageProcessorError: Error, Equatable {
    case cannotDecodeSource
    case cannotEncodeJPEG
    case cannotFit(maxBytes: Int)
}

public struct ImageProcessor {

    /// Decodes `sourceData` then resize-and-encode-to-fit. Existing PhotosPicker
    /// entrypoint — behavior unchanged from Phase C.
    public static func encodeJPEG(
        sourceData: Data,
        maxBytes: Int = 1_000_000,
        maxLongerEdge: Int = 2048
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int) {

        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageProcessorError.cannotDecodeSource
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let originalWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let originalHeight = props[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageProcessorError.cannotDecodeSource
        }

        let minimumLongerEdge = 256
        var currentMax = maxLongerEdge

        while currentMax >= minimumLongerEdge {
            let cgImage = try renderImage(
                from: source,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                maxLongerEdge: currentMax
            )

            if let fitted = try encodeFitting(cgImage: cgImage, maxBytes: maxBytes) {
                return fitted
            }

            currentMax /= 2
        }

        throw ImageProcessorError.cannotFit(maxBytes: maxBytes)
    }

    /// Encode-to-fit for a CGImage already at its final dimensions. Used by
    /// the Camera path which produces a cropped CGImage and doesn't need
    /// the outer `currentMax` halving loop. If the image doesn't fit at the
    /// lowest tried quality, throws `.cannotFit`.
    public static func encodeJPEG(
        cgImage: CGImage,
        maxBytes: Int = 1_000_000
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int) {
        if let fitted = try encodeFitting(cgImage: cgImage, maxBytes: maxBytes) {
            return fitted
        }
        throw ImageProcessorError.cannotFit(maxBytes: maxBytes)
    }

    // MARK: - Internals

    /// Walks the explicit quality ladder; returns the highest-fidelity-that-fits
    /// or nil if even quality 0.30 is over the cap.
    private static func encodeFitting(
        cgImage: CGImage,
        maxBytes: Int
    ) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int)? {
        let qualities: [Double] = [0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30]
        for quality in qualities {
            let data = try encode(cgImage: cgImage, quality: quality)
            if data.count <= maxBytes {
                return (data, cgImage.width, cgImage.height)
            }
        }
        return nil
    }

    private static func renderImage(
        from source: CGImageSource,
        originalWidth: Int,
        originalHeight: Int,
        maxLongerEdge: Int
    ) throws -> CGImage {
        let needsDownsample = max(originalWidth, originalHeight) > maxLongerEdge
        if !needsDownsample {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ImageProcessorError.cannotDecodeSource
            }
            return image
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongerEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessorError.cannotDecodeSource
        }
        return thumbnail
    }

    private static func encode(cgImage: CGImage, quality: Double) throws -> Data {
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer, "public.jpeg" as CFString, 1, nil
        ) else {
            throw ImageProcessorError.cannotEncodeJPEG
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality as CFNumber,
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageProcessorError.cannotEncodeJPEG
        }
        return buffer as Data
    }
}
```

- [ ] **Step 4: Run tests to verify both old and new suites pass**

```bash
swift test --filter ImageProcessorCGImageOverloadTests
swift test --filter ComposeTests
```

Expected: new suite reports `3 passed`. The full ComposeTests suite still passes (the refactor preserves behavior for the existing `sourceData:` callers — pre-Phase C image tests should be untouched).

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/ImageProcessor.swift Tests/ComposeTests/ComposeTests.swift
git commit -m "feat(image): encodeJPEG(cgImage:) overload + internal refactor (J1.B)

Extract the quality-bisect inner loop into a private helper and expose
a CGImage-taking overload for the camera path (no re-decode of bytes we
just produced). Existing encodeJPEG(sourceData:) is unchanged from
callers' perspective.

3 new tests cover the overload; existing ComposeTests stay green.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.C — `CameraPermissionResolver` + protocol (TDD)

**Files:**
- Create: `Sources/Camera/CameraPermissionResolver.swift`
- Create: `Tests/CameraTests/CameraPermissionResolverTests.swift`

Inject the AVFoundation permission surface behind a tiny protocol so the resolver is unit-testable on macOS (where AVCaptureDevice is unavailable).

- [ ] **Step 1: Write the failing test file**

Create `Tests/CameraTests/CameraPermissionResolverTests.swift`:

```swift
import Testing
@testable import Camera

@Suite("CameraPermissionResolver")
struct CameraPermissionResolverTests {

    @Test
    func authorizedProviderReturnsAuthorizedWithoutRequesting() async {
        let provider = StubPermissionProvider(status: .authorized, grants: false)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .authorized)
        #expect(provider.didCallRequest == false)
    }

    @Test
    func notDeterminedAndGrantedReturnsAuthorized() async {
        let provider = StubPermissionProvider(status: .notDetermined, grants: true)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .authorized)
        #expect(provider.didCallRequest == true)
    }

    @Test
    func notDeterminedAndDeniedReturnsDenied() async {
        let provider = StubPermissionProvider(status: .notDetermined, grants: false)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .denied)
        #expect(provider.didCallRequest == true)
    }

    @Test
    func deniedProviderReturnsDeniedWithoutRequesting() async {
        let provider = StubPermissionProvider(status: .denied, grants: true)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .denied)
        #expect(provider.didCallRequest == false)
    }

    @Test
    func restrictedProviderReturnsDenied() async {
        let provider = StubPermissionProvider(status: .restricted, grants: false)
        let result = await CameraPermissionResolver.resolve(using: provider)
        #expect(result == .denied)
    }
}

// MARK: - Stub

private final class StubPermissionProvider: CameraPermissionProviding, @unchecked Sendable {
    let initialStatus: CameraAuthorizationStatus
    let grantOnRequest: Bool
    var didCallRequest = false

    init(status: CameraAuthorizationStatus, grants: Bool) {
        self.initialStatus = status
        self.grantOnRequest = grants
    }

    func currentStatus() -> CameraAuthorizationStatus { initialStatus }

    func requestAccess() async -> Bool {
        didCallRequest = true
        return grantOnRequest
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter CameraPermissionResolverTests
```

Expected: build fails with `cannot find 'CameraPermissionProviding' in scope` and similar. Red-bar.

- [ ] **Step 3: Implement the resolver**

Create `Sources/Camera/CameraPermissionResolver.swift`:

```swift
// CameraPermissionResolver — pure resolution layer over the AVFoundation
// permission API. Injectable for tests (macOS has no AVCaptureDevice).
//
// The resolver collapses Apple's 4-case status into 2 outcomes the UI
// actually cares about: .authorized (proceed) and .denied (show settings
// card). `.notDetermined` triggers a prompt; everything else is terminal.

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Mirror of `AVAuthorizationStatus` that compiles cross-platform.
public enum CameraAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Resolved camera permission state — what the UI binds to.
public enum CameraPermissionState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Injection seam — the live impl wraps AVCaptureDevice; tests stub it.
public protocol CameraPermissionProviding: Sendable {
    func currentStatus() -> CameraAuthorizationStatus
    func requestAccess() async -> Bool
}

public enum CameraPermissionResolver {

    /// Returns the resolved state, prompting via `requestAccess` only when
    /// the current status is `.notDetermined`.
    public static func resolve(using provider: CameraPermissionProviding) async -> CameraPermissionState {
        switch provider.currentStatus() {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let granted = await provider.requestAccess()
            return granted ? .authorized : .denied
        }
    }
}

#if canImport(AVFoundation)

/// Production provider — wraps `AVCaptureDevice` directly.
public struct LiveCameraPermissionProvider: CameraPermissionProviding {

    public init() {}

    public func currentStatus() -> CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

#endif
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter CameraPermissionResolverTests
```

Expected: `5 passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Camera/CameraPermissionResolver.swift Tests/CameraTests/CameraPermissionResolverTests.swift
git commit -m "feat(camera): CameraPermissionResolver + protocol (J1.C)

Pure resolver that collapses AVAuthorizationStatus into the 2 outcomes
the UI cares about (authorized | denied), behind a CameraPermissionProviding
protocol. Live impl wraps AVCaptureDevice and is only compiled on
platforms with AVFoundation. 5 tests cover the four input states + the
no-double-request invariant.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.D — Foundations: `Log.media` + `NSCameraUsageDescription`

**Files:**
- Modify: `Sources/AppLogging/Log.swift` — add `media` logger
- Modify: `App/Resources/Info.plist` — add `NSCameraUsageDescription`

No new types, no new tests. The `Log.media` add is two lines; the Info.plist add is the privacy string. Both are prerequisites for J1.E.

- [ ] **Step 1: Add `Log.media`**

Edit `Sources/AppLogging/Log.swift`. The file currently has 4 loggers (`auth`, `network`, `storage`, `ui`). Add `media` between `storage` and `ui` (alphabetical-ish; matches existing rhythm):

```swift
public static let auth    = Logger(subsystem: subsystem, category: "auth")
public static let media   = Logger(subsystem: subsystem, category: "media")
public static let network = Logger(subsystem: subsystem, category: "network")
public static let storage = Logger(subsystem: subsystem, category: "storage")
public static let ui      = Logger(subsystem: subsystem, category: "ui")
```

- [ ] **Step 2: Verify the package still builds**

```bash
swift build
```

Expected: `Build complete!`.

- [ ] **Step 3: Add `NSCameraUsageDescription` to Info.plist**

Edit `App/Resources/Info.plist`. Find the closing `</dict>` near the end. Add this key/value pair immediately before it (keeping the existing whitespace style — tab indentation, alphabetical-ish placement isn't required by Apple):

```xml
	<key>NSCameraUsageDescription</key>
	<string>Take a photo to attach to your Bluesky post.</string>
```

- [ ] **Step 4: Verify the Xcode project still builds**

```bash
cd App && xcodegen generate && cd ..
xcodebuild build \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  -derivedDataPath /tmp/bst-derived 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppLogging/Log.swift App/Resources/Info.plist
git commit -m "feat(camera): Log.media + NSCameraUsageDescription (J1.D)

Plumbing for J1.E. New 'media' OSLog category alongside existing
auth/network/storage/ui. Privacy string lets us call camera APIs
without the iOS-enforced crash.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.E — `CameraSession` (iOS-only AVFoundation wrapper)

**Files:**
- Create: `Sources/Camera/CameraSession.swift`

`@MainActor @Observable` wrapper around `AVCaptureSession` + `AVCapturePhotoOutput`. All session mutation hops to a private serial queue. Photo delegate runs the crop + encode pipeline. No unit tests (AVFoundation requires a device); verification is by `swift build` + `xcodebuild build` succeeding and a manual smoke check.

- [ ] **Step 1: Create `CameraSession.swift`**

Create `Sources/Camera/CameraSession.swift`:

```swift
// CameraSession — @MainActor @Observable wrapper around AVCaptureSession.
//
// All configuration and start/stop hops to a private serial sessionQueue
// per axiom-media (startRunning blocks for seconds — never on main).
// AVCapturePhotoCaptureDelegate methods are nonisolated; they finish the
// pipeline on the session queue (crop + JPEG encode are CPU-bound, not
// MainActor-relevant) then publish the result back to MainActor.
//
// iOS-only: the entire type is gated by `#if os(iOS)` so macOS swift test
// runs of CameraTests don't try to import AVFoundation surfaces that
// behave differently on macOS (AVCaptureDevice exists but has no camera).

#if os(iOS)

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import AppLogging
import Models
import Observation

@MainActor
@Observable
public final class CameraSession: NSObject {

    public enum State: Equatable {
        case idle                                  // before requestPermissionAndStart()
        case resolvingPermission
        case denied
        case unavailable                            // no camera device on this hardware
        case live                                   // viewfinder running, ready for shutter
        case capturing
        case captured(jpegData: Data, pixelWidth: Int, pixelHeight: Int)
        case failed(message: String)
    }

    public private(set) var state: State = .idle

    public let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.dtolb.BlueSkyTemplates.camera.session",
                                             qos: .userInitiated)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var interruptionObservers: [NSObjectProtocol] = []

    private let permissionProvider: any CameraPermissionProviding

    public init(permissionProvider: any CameraPermissionProviding = LiveCameraPermissionProvider()) {
        self.permissionProvider = permissionProvider
        super.init()
        setupInterruptionHandling()
    }

    deinit {
        interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Lifecycle

    public func requestPermissionAndStart() async {
        state = .resolvingPermission
        let resolved = await CameraPermissionResolver.resolve(using: permissionProvider)
        switch resolved {
        case .authorized:
            await configureAndStart()
        case .denied:
            state = .denied
        case .notDetermined:
            // Resolver guarantees a terminal state, but be defensive.
            state = .denied
        }
    }

    public func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    public func resume() {
        // After Retake: state is .captured(...); flip back to .live and the
        // preview keeps streaming (session never stopped).
        state = .live
    }

    // MARK: - Capture

    public func capture() {
        guard case .live = state else { return }
        state = .capturing
        let rotationAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0
        sessionQueue.async { [photoOutput] in
            if let connection = photoOutput.connection(with: .video) {
                connection.videoRotationAngle = rotationAngle
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Configuration

    private func configureAndStart() async {
        // Check device availability up-front; the iPhone 17 simulator has no
        // back wide-angle camera and would otherwise fail silently.
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            state = .unavailable
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                let configured = configureSessionSync()
                DispatchQueue.main.async {
                    if configured {
                        // session.startRunning() is a blocking call; do it on the queue.
                        self.sessionQueue.async {
                            if !self.session.isRunning { self.session.startRunning() }
                        }
                        self.state = .live
                    } else {
                        self.state = .failed(message: "Couldn't start camera.")
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Returns true on success. Runs on sessionQueue.
    private func configureSessionSync() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            Log.media.error("camera input add failed")
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            Log.media.error("camera photo output add failed")
            return false
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        // RotationCoordinator setup happens on main — the preview layer it
        // observes is owned by the SwiftUI representable. Done by caller via
        // attachRotationCoordinator(...) after the preview is mounted.
        return true
    }

    /// Wired from `CameraPreviewLayer.makeUIView` once the preview layer exists.
    /// Sets up the iOS 17+ RotationCoordinator so preview + capture stay correctly
    /// oriented even when the device is face-up / face-down.
    public func attachRotationCoordinator(previewLayer: AVCaptureVideoPreviewLayer) {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak previewLayer] coordinator, _ in
            DispatchQueue.main.async {
                previewLayer?.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            }
        }
    }

    // MARK: - Interruption handling

    private func setupInterruptionHandling() {
        let interrupted = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let reason: String
            if let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int {
                reason = "\(raw)"
            } else {
                reason = "unknown"
            }
            Log.media.info("camera session interrupted: \(reason, privacy: .public)")
            // We don't flip state — the UI shows a banner via its own observer.
            _ = self
        }
        interruptionObservers.append(interrupted)

        let ended = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { _ in
            Log.media.info("camera session interruption ended")
        }
        interruptionObservers.append(ended)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraSession: AVCapturePhotoCaptureDelegate {

    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Log.media.error("photo capture failed: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't take photo.")
            }
            return
        }

        guard let jpegData = photo.fileDataRepresentation() else {
            Log.media.error("nil photo data representation")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't read photo data.")
            }
            return
        }

        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Log.media.error("photo decode failed")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't decode photo.")
            }
            return
        }

        let squareImage = CenterSquareCrop.crop(fullImage)

        let encoded: (data: Data, pixelWidth: Int, pixelHeight: Int)
        do {
            encoded = try ImageProcessor.encodeJPEG(cgImage: squareImage, maxBytes: 1_000_000)
        } catch {
            Log.media.error("encode failed: \(String(describing: error), privacy: .public)")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't encode photo.")
            }
            return
        }

        Task { @MainActor [weak self] in
            self?.state = .captured(
                jpegData: encoded.data,
                pixelWidth: encoded.pixelWidth,
                pixelHeight: encoded.pixelHeight
            )
        }
    }
}

#endif
```

- [ ] **Step 2: Verify SPM compiles**

```bash
swift build
```

Expected: `Build complete!` — Camera target compiles. (On macOS, the file is entirely `#if os(iOS)`-gated and contributes nothing; the target still has CenterSquareCrop + CameraPermissionResolver.)

- [ ] **Step 3: Verify iOS app compiles**

```bash
cd App && xcodegen generate && cd ..
xcodebuild build \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  -derivedDataPath /tmp/bst-derived 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify all tests still pass**

```bash
swift test
```

Expected: every suite green. No new tests added in J1.E (AVFoundation is integration-tested in J1.G manual verification).

- [ ] **Step 5: Commit**

```bash
git add Sources/Camera/CameraSession.swift
git commit -m "feat(camera): CameraSession @Observable AV wrapper (J1.E)

@MainActor @Observable type. AVCaptureSession config + start/stop on a
private serial sessionQueue. Photo delegate decodes → CenterSquareCrop
→ ImageProcessor.encodeJPEG(cgImage:) → hops to MainActor with the
.captured(data, w, h) state. RotationCoordinator wired for iOS 17+.
Interruption observers log; the UI surfaces the banner. iPhone 17 sim
hits .unavailable since AVCapture has no real device there.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.F — `CameraPreviewLayer` + `SquareCameraView` (iOS-only UI)

**Files:**
- Create: `Sources/Camera/CameraPreviewLayer.swift`
- Create: `Sources/Camera/SquareCameraView.swift`

Two files, one task — they're tightly coupled (the SquareCameraView mounts the preview layer). No unit tests; verify both `swift build` and `xcodebuild build` succeed. Manual verification of UI happens in J1.H.

- [ ] **Step 1: Create `CameraPreviewLayer.swift`**

Create `Sources/Camera/CameraPreviewLayer.swift`:

```swift
// CameraPreviewLayer — UIViewRepresentable wrapping AVCaptureVideoPreviewLayer.
// Pattern 2 from axiom-media camera-capture.md, adapted for our CameraSession.
//
// The `onPreviewReady` callback fires once the preview layer is mounted so
// CameraSession can attach its RotationCoordinator (which needs the layer
// reference). Fires on the main actor.

#if os(iOS)

import SwiftUI
import AVFoundation

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    let onPreviewReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            onPreviewReady(view.previewLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#endif
```

- [ ] **Step 2: Create `SquareCameraView.swift`**

Create `Sources/Camera/SquareCameraView.swift`:

```swift
// SquareCameraView — full-screen sheet that owns CameraSession's lifetime.
//
// Viewfinder: full-bleed preview with opaque top + bottom letterbox so the
// visible window is exactly square. Shutter button bottom-center, Cancel
// top-leading.
// Review: the captured square photo at full bleed, with Retake + Use Photo.
// Denied: settings-redirect card. Unavailable: device-has-no-camera card.

#if os(iOS)

import SwiftUI
import AVFoundation
import UIKit
import DesignSystem

public struct SquareCameraView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var session = CameraSession()

    /// Called when the user taps Use Photo on the review screen. The sheet
    /// dismisses itself after the callback returns.
    let onCapture: (Data, Int, Int) -> Void

    public init(onCapture: @escaping (Data, Int, Int) -> Void) {
        self.onCapture = onCapture
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .task {
            // Re-check every time the sheet appears so a user who toggled
            // permission in Settings comes back to a working viewfinder.
            await session.requestPermissionAndStart()
        }
        .onDisappear {
            session.stop()
        }
    }

    // MARK: - State-routed content

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .idle, .resolvingPermission:
            ProgressView().tint(.white)
        case .denied:
            permissionDeniedCard
        case .unavailable:
            unavailableCard
        case .live, .capturing:
            viewfinder
        case .captured(let data, let w, let h):
            reviewScreen(data: data, width: w, height: h)
        case .failed(let message):
            failureCard(message: message)
        }
    }

    // MARK: - Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    CameraPreviewLayer(session: session.session) { previewLayer in
                        session.attachRotationCoordinator(previewLayer: previewLayer)
                    }
                    .frame(width: side, height: side)
                    .clipped()
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .top) { cancelBar }
            .overlay(alignment: .bottom) { shutterBar }
        }
    }

    private var cancelBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .accessibilityLabel("Cancel and close camera")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var shutterBar: some View {
        VStack(spacing: 12) {
            if case .failed(let msg) = session.state {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColor.error)
                    .font(.callout)
                    .padding(.horizontal, 16)
            }
            Button {
                session.capture()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.6), lineWidth: 4)
                            .frame(width: 84, height: 84)
                    )
            }
            .disabled(!isShutterEnabled)
            .accessibilityLabel("Take photo")
            .padding(.bottom, 32)
        }
    }

    private var isShutterEnabled: Bool {
        if case .live = session.state { return true }
        return false
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewScreen(data: Data, width: Int, height: Int) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.gray)
                        .frame(width: side, height: side)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) {
                HStack(spacing: 24) {
                    Button("Retake") { session.resume() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Use Photo") {
                        onCapture(data, width, height)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 32)
            }
            .overlay(alignment: .top) { cancelBar }
        }
    }

    // MARK: - Cards

    private var permissionDeniedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))
            Text("Camera access is off")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("BlueSky Templates needs camera access to take photos.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .padding(32)
    }

    private var unavailableCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))
            Text("No camera on this device")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("This device doesn't have a camera the app can access. Try on a physical iPhone or iPad.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func failureCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(BrandColor.error)
            Text(message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

// MARK: - Preview

#Preview("Camera — denied state") {
    SquareCameraView { _, _, _ in }
}

#endif
```

- [ ] **Step 3: Verify SPM build**

```bash
swift build
```

Expected: `Build complete!`.

- [ ] **Step 4: Verify iOS app build**

```bash
cd App && xcodegen generate && cd ..
xcodebuild build \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  -derivedDataPath /tmp/bst-derived 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify all tests still pass**

```bash
swift test
```

Expected: every suite green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Camera/CameraPreviewLayer.swift Sources/Camera/SquareCameraView.swift
git commit -m "feat(camera): CameraPreviewLayer + SquareCameraView UI (J1.F)

UIViewRepresentable wrapping AVCaptureVideoPreviewLayer (fires
onPreviewReady so CameraSession can attach its RotationCoordinator).
SquareCameraView is the full-screen sheet — viewfinder with bottom-bar
shutter, review screen with Use/Retake, plus denied/unavailable/failed
cards. State-routed via CameraSession.State.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.G — Wire Camera into Compose

**Files:**
- Modify: `Package.swift` — add `Camera` to `Compose` target dependencies
- Modify: `Sources/Compose/ComposeView.swift` — add camera button, sheet presentation, `ingestCameraCapture`

- [ ] **Step 1: Add `Camera` to `Compose` dependencies in `Package.swift`**

Edit the `Compose` target. Currently:

```swift
.target(
    name: "Compose",
    dependencies: [
        "Auth",
        "Bluesky",
        "DesignSystem",
        "AppLogging",
        "Models",
        "Templates",
        .product(name: "Pow", package: "Pow"),
    ]
),
```

Add `"Camera"` alphabetically (between `Bluesky` and `DesignSystem`):

```swift
.target(
    name: "Compose",
    dependencies: [
        "Auth",
        "Bluesky",
        "Camera",
        "DesignSystem",
        "AppLogging",
        "Models",
        "Templates",
        .product(name: "Pow", package: "Pow"),
    ]
),
```

- [ ] **Step 2: Modify `ComposeView.swift` — import Camera and add state**

Open `Sources/Compose/ComposeView.swift`. At the top, alongside other module imports, add:

```swift
import Camera
```

Inside `public struct ComposeView: View {`, just below the existing `#if canImport(PhotosUI)` `@State` block:

```swift
#if canImport(PhotosUI)
@State private var pickerSelection: [PhotosPickerItem] = []
@State private var attachmentError: String?
#endif

#if os(iOS)
@State private var cameraPresented: Bool = false
#endif
```

- [ ] **Step 3: Replace the PhotosPicker row with an HStack containing the camera button**

In the `Section { ... } header: { BrandSectionHeader("Images") }` block, find this:

```swift
#if canImport(PhotosUI)
let currentCount = attachments.count
PhotosPicker(
    selection: $pickerSelection,
    maxSelectionCount: ComposeText.attachmentLimit - currentCount,
    matching: .images,
    photoLibrary: .shared()
) {
    Label("Add image (\(currentCount)/\(ComposeText.attachmentLimit))", systemImage: "photo.badge.plus")
}
.disabled(!ComposeText.canAttach(currentCount: currentCount) || isSending)
#else
Text("Image attachments are iOS-only.")
    .foregroundStyle(.secondary)
#endif
```

Replace with:

```swift
#if canImport(PhotosUI)
let currentCount = attachments.count
HStack {
    PhotosPicker(
        selection: $pickerSelection,
        maxSelectionCount: ComposeText.attachmentLimit - currentCount,
        matching: .images,
        photoLibrary: .shared()
    ) {
        Label("Add image (\(currentCount)/\(ComposeText.attachmentLimit))", systemImage: "photo.badge.plus")
    }
    .disabled(!ComposeText.canAttach(currentCount: currentCount) || isSending)
    #if os(iOS)
    Spacer()
    Button {
        cameraPresented = true
    } label: {
        Image(systemName: "camera")
            .font(.body.weight(.semibold))
            .frame(width: 36, height: 36)
    }
    .buttonStyle(.borderless)
    .disabled(!ComposeText.canAttach(currentCount: currentCount) || isSending)
    .accessibilityLabel("Take photo")
    #endif
}
#else
Text("Image attachments are iOS-only.")
    .foregroundStyle(.secondary)
#endif
```

- [ ] **Step 4: Add the sheet modifier and the ingest callback**

The `ComposeView.body` ends with a modifier chain on the `NavigationStack`. The very last modifier in that chain is the `#if canImport(PhotosUI) ... .onChange(of: pickerSelection) { ... } ... #endif` block (around lines 286–301 of the pre-J1 file). Add the new sheet modifier **immediately after the closing `#endif` of that PhotosUI block, still inside the `NavigationStack` modifier chain**:

```swift
            #endif  // existing closing #endif of the PhotosUI onChange block
            #if os(iOS)
            .sheet(isPresented: $cameraPresented) {
                SquareCameraView { data, width, height in
                    ingestCameraCapture(data: data, pixelWidth: width, pixelHeight: height)
                }
            }
            #endif
        }   // closes the NavigationStack
    }       // closes body
```

Then, add the new helper method inside `ComposeView`, immediately after the existing `private func ingest(items:)` method (the PhotosPicker ingest — search for `private func ingest(items: [PhotosPickerItem])`):

```swift
#if os(iOS)
@MainActor
private func ingestCameraCapture(data: Data, pixelWidth: Int, pixelHeight: Int) {
    guard attachments.count < ComposeText.attachmentLimit else { return }
    attachments.append(ComposeAttachment(
        jpegData: data,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight
    ))
    attachmentError = nil
}
#endif
```

- [ ] **Step 5: Verify SPM build**

```bash
swift build
```

Expected: `Build complete!`.

- [ ] **Step 6: Verify iOS app build**

```bash
cd App && xcodegen generate && cd ..
xcodebuild build \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  -derivedDataPath /tmp/bst-derived 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Verify tests pass**

```bash
swift test
```

Expected: every suite green.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/Compose/ComposeView.swift
git commit -m "feat(compose): wire camera button into Images section (J1.G)

PhotosPicker stays; new trailing 'Take photo' camera button opens
SquareCameraView in a sheet. Captures land via ingestCameraCapture(...)
which appends a ComposeAttachment with the same shape the PhotosPicker
path produces — alt-text, send-gating, 4-image cap all reuse the existing
plumbing.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task J1.H — Documentation: manual test plan + kanban entry

**Files:**
- Append: `docs/ui-test-backlog.md` — manual verification checklist
- Append: `kanban.md` — Phase J1 entry under In Flight or Shipped

- [ ] **Step 1: Append the manual test plan to `docs/ui-test-backlog.md`**

Open `docs/ui-test-backlog.md`. Append a new section at the end (keep existing content untouched):

```markdown
## Phase J1 — Square camera capture

Manual verification, on a physical iPhone/iPad signed into iCloud. Items
marked ⚠️ require teardown across multiple app sessions.

- [ ] First-launch permission prompt appears the first time camera button is tapped
- [ ] Granting permission → live square viewfinder, shutter visible
- [ ] Shutter → review screen shows captured 1:1 photo
- [ ] Use Photo → sheet dismisses, photo lands in Compose Images as a new row
- [ ] Attached photo has correct 1:1 aspect ratio in the row thumbnail
- [ ] Alt-text field is empty and required (Send disabled until non-blank)
- [ ] Retake from review → returns to live viewfinder, no flicker, session keeps running
- [ ] Cancel (X) from viewfinder → sheet dismisses, no attachment created
- [ ] Cancel from review → sheet dismisses, no attachment created
- [ ] Take 4 photos via camera → camera button + PhotosPicker both disable (4-image cap)
- [ ] ⚠️ Deny permission once → camera card shows "Camera access is off" with Open Settings
- [ ] ⚠️ From Settings, toggle camera on → return to app → tap camera button → viewfinder works
- [ ] ⚠️ Take a photo → leave app → return → camera state is fresh on next open
- [ ] Phone call mid-capture → banner appears (or capture pauses), recovers cleanly on hang-up
- [ ] Face-up capture (device flat on a table) → captured EXIF orientation is correct
- [ ] iPhone 17 simulator → camera button → "No camera on this device" card (not a crash)
- [ ] Post a captured photo end-to-end → appears on Bluesky with 1:1 aspect ratio
```

- [ ] **Step 2: Add a kanban entry**

Open `kanban.md`. Add the Phase J1 entry to the appropriate column (In Flight if you want to leave the manual verification pending, Shipped if you're closing it out immediately):

```markdown
- **Phase J1 — Square camera capture** — live 1:1 viewfinder in Compose,
  Use/Retake review, RotationCoordinator-driven EXIF. Spec:
  [docs/specs/2026-05-22-square-camera-capture-design.md](docs/specs/2026-05-22-square-camera-capture-design.md).
  Manual test plan: docs/ui-test-backlog.md § Phase J1.
```

- [ ] **Step 3: Commit**

```bash
git add docs/ui-test-backlog.md kanban.md
git commit -m "docs(j1): manual test plan + kanban entry for square camera (J1.H)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks complete)

After J1.H commits, run the full test suite and a final app build:

```bash
swift test
cd App && xcodegen generate && cd ..
xcodebuild build \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  -derivedDataPath /tmp/bst-derived 2>&1 | tail -5
```

Expected:
- All tests green
- `** BUILD SUCCEEDED **`

The remaining acceptance criteria (real camera on a physical device) are checked
off via the `docs/ui-test-backlog.md § Phase J1` checklist by the user.
