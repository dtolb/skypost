# Phase J2 — native camera controls: implementation plan

**Goal:** Extend the J1 custom camera capture sheet from fixed square/back-wide capture to a native-feeling photo flow with hardware zoom toggles, portrait/landscape framing, and ratio selection between Default and 1:1.

**Research decision:** Keep the custom `AVCaptureSession` + `AVCapturePhotoOutput` path instead of `UIImagePickerController`. Apple documents `AVCapturePhotoSettings` as the photo-capture request shape, `RotationCoordinator` as the modern way to keep capture/preview level, `builtInTripleCamera` as the virtual device for ultrawide/wide/tele switching, `virtualDeviceSwitchOverVideoZoomFactors` for lens switch-over points, and `displayVideoZoomFactorMultiplier` for native UI labels. iOS 26 also exposes dynamic aspect-ratio APIs, but this phase intentionally relies on preview framing + post-capture crop because the app already needs exact Compose attachment dimensions and `setDynamicAspectRatio` produced noisy Fig backend errors on device testing.

**UX decisions:**

- Use the best available back virtual camera in this order: triple, dual-wide, dual, wide. Do not manually swap three physical inputs for lens buttons; native camera UX is zoom-factor-driven on the virtual device.
- Build zoom chips from `[minAvailableVideoZoomFactor] + virtualDeviceSwitchOverVideoZoomFactors`, labeled with `displayVideoZoomFactorMultiplier`. On a triple camera this produces native-style values like `0.5x`, `1x`, `3x`.
- Default to native `Default` ratio with portrait framing; keep `1:1` available as a visible segmented option.
- Portrait/landscape is a capture-framing toggle, not app orientation. iPhone remains portrait-only per `App/project.yml`.
- Always center-crop to the selected framing after capture before JPEG encode, so the output matches the preview.

## TDD task list

- [x] **J2.A — Pure framing model.** Add `CameraCaptureRatio`, `CameraCaptureOrientation`, `CameraAspectRatio`, and `CameraCaptureConfiguration`; unit-test square/default target aspect and preview sizing.
- [x] **J2.B — Generic crop helper.** Add `CenterAspectCrop` and route `CenterSquareCrop` through it; unit-test portrait, landscape, matching-aspect, and square parity cases.
- [x] **J2.C — Zoom option model.** Add `CameraZoomOption.options(...)` and default selection; unit-test triple-camera labels, single-camera fallback, duplicate removal, and 1x default selection.
- [x] **J2.D — JPEG safety for default-ratio photos.** Extend `ImageProcessor.encodeJPEG(cgImage:)` with max-longer-edge downsampling; unit-test a large noisy CGImage fitting under 1 MB.
- [x] **J2.E — AVFoundation session wiring.** Prefer virtual back camera, expose selected ratio/orientation/zoom state, ramp zoom changes on the session queue, and process captures through `CenterAspectCrop`.
- [x] **J2.F — Camera sheet UI.** Rename `SquareCameraView` to `CameraCaptureView`; add ratio segmented control, orientation icon toggles, and zoom chips while keeping the Use/Retake review flow.
- [x] **J2.G — Compose integration.** Present `CameraCaptureView` from Compose; downstream `ComposeAttachment` ingestion stays unchanged.
- [x] **J2.H — Verification.** Run `swift test`, regenerate XcodeGen project, run iPhone 17 simulator `xcodebuild build`, run the app on simulator, and complete fresh-context subagent review before opening the MR.

## Verification commands

```sh
swift test
cd App && xcodegen generate
xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
```

Simulator limitation: iPhone 17 Simulator has no real camera device, so local UI validation can verify sheet presentation and the unavailable-camera card. Physical-device verification is still needed for live preview, zoom switching, and real capture output.
