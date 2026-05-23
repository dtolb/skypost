# BlueSkyTemplates

A personal iOS app for posting templated Bluesky posts.

## Status

**v2 is on `main`.** Shipped so far: app-password sign-in and restore,
Templates CRUD, Compose with text/images/link cards, template picker and
template apply flow, Mantis styling, iCloud-backed template storage,
template JSON import/export, a Create Template App Intent, and dark-mode
safe card/icon surfaces. Compose also has custom camera capture with
Default/1:1 framing, portrait/landscape capture framing, and native-style
rear-camera zoom chips.

The live task board is [`kanban.md`](kanban.md). The most recent plan is
[`docs/plans/2026-05-22-phase-j2-camera-controls.md`](docs/plans/2026-05-22-phase-j2-camera-controls.md).

## Build & run

Prerequisites:

- Xcode 26.5 (iOS 26 SDK).
- XcodeGen — `brew install xcodegen`.
- An **iPhone 17** simulator from the iOS 26 runtime (iPhone 15 was
  retired in Xcode 26).
- Apple Development signing for team `49LQ789275`. The iCloud/CloudKit
  entitlements cannot use Xcode's "Sign to Run Locally" identity.

Commands:

```sh
# Xcode dev — generate the project, then open it.
cd App && xcodegen generate && open BlueSkyTemplates.xcodeproj

# SPM library targets — build and test from the repo root.
swift build
swift test

# Headless Xcode build (matches CI).
xcodebuild build \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The `.xcodeproj` is gitignored and must be regenerated from
`App/project.yml` after every checkout. XcodeGen pins automatic
development signing for the app target because iCloud entitlements require
a real Apple Development identity.

## Project layout

- `App/` — the iOS app target. `project.yml` is the XcodeGen spec; the
  generated `BlueSkyTemplates.xcodeproj` depends on the SPM library
  products and contains the `Info.plist`, asset catalog, and the
  `AppMain.swift` shim that calls into `BlueSkyTemplatesApp`.
- `Sources/` — the SPM workspace defined by `Package.swift`. All
  application code lives here as library modules:
  - `BlueSkyTemplatesApp` — composition root; owns the single `APIClient`
    and `AuthService` and wires the SwiftUI scene.
  - `Auth` — `AuthProvider` protocol, `AppPasswordAuth` implementation,
    `AuthService` state machine, and `LoginView`.
  - `Bluesky` — the only module that imports ATProtoKit. Wraps the SDK
    behind an `actor APIClient` and a Keychain-backed session store.
  - `Models` — shared DTOs (`SessionInfo`, `APIError`) with no framework
    dependencies.
  - `Templates` — SwiftData `@Model Template`, CloudKit storage wiring,
    JSON template exchange, and Templates CRUD UI.
  - `Compose` — post-composition feature with text, image attachment,
    external link card, template picker, and send-state handling.
  - `Camera` — AVFoundation photo capture flow with ratio/orientation
    framing, zoom chips, preview/review UI, and post-capture JPEG crop.
  - `DesignSystem` — typography, color, gradient, card, header, icon, and
    hero primitives, including dynamic page/card/icon surfaces for light and
    dark appearances.
  - `AppLogging` — `os.Logger` categories and a `SecItem` Keychain
    wrapper.
- `Tests/` — `swift test` targets paralleling the source modules
  (`AuthTests`, `BlueskyTests`, `ComposeTests`, `TemplatesTests`).
- `docs/` — long-lived planning and review artifacts. See
  [`docs/README.md`](docs/README.md).

**Module-boundary rule:** only `Bluesky` imports `ATProtoKit`. Every
other module talks to Bluesky through `APIClient` and the types in
`Models`.

Template user content is stored through SwiftData. The app uses the
private CloudKit container `iCloud.com.dtolb.BlueSkyTemplates` when the
app entitlement/provisioning allows it, and falls back to a local
SwiftData store if CloudKit initialization fails. Template import/export
uses versioned JSON handled by the `Templates` module.

## Architecture spec

The source of truth for the v2 design lives at
[`docs/architecture.md`](docs/architecture.md). It covers the target
stack, module layout, isolation model, logging discipline, the
ATProtoKit pinning rationale, and the auth strategy (app passwords now,
OAuth later behind the same `AuthProvider`).

## CI

GitLab CI on <https://gitlab.tolbbox.com>. Both jobs (`build`, `test`)
are tagged `xcode` to route to the Mac shell runner (the `macos` tag
points at a Docker runner that can't run `xcodebuild`). `swift test
--xunit-output` produces JUnit XML that GitLab parses into per-test
pass/fail on the MR widget.

Pipelines: <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/pipelines>

## Dependencies

Pinned in `Package.swift`.

| Package | Pin | Role |
| --- | --- | --- |
| [ATProtoKit](https://github.com/MasterJ93/ATProtoKit) | `0.32.5..<0.33.0` | Bluesky / atproto SDK. Imported only by `Bluesky`. |
| [Nuke](https://github.com/kean/Nuke) | `13.0.6..<14.0.0` | Image loading, pinned for future feed/CDN URL surfaces. |
| [Pow](https://github.com/EmergeTools/Pow) | `from: 1.0.6` | SwiftUI send/error effects. |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | `2.4.1..<3.0.0` | Markdown rendering for bios and help (unused yet). |

## License

Personal project, no license offered.
