# BlueSkyTemplates

A personal iOS app for posting templated Bluesky posts.

## Status

**v2 rewrite in progress on branch `v2`** (will merge to `main` shortly).
Shipped so far: app-password sign-in, session restore, and a hello-world
post path. The live todo list lives in
[`docs/plans/`](docs/plans/); the most recent is
[`docs/plans/2026-05-20-review-fixes.md`](docs/plans/2026-05-20-review-fixes.md).

## Build & run

Prerequisites:

- Xcode 26.5 (iOS 26 SDK).
- XcodeGen — `brew install xcodegen`.
- An **iPhone 17** simulator from the iOS 26 runtime (iPhone 15 was
  retired in Xcode 26).

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
`App/project.yml` after every checkout.

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
  - `Templates` — SwiftData `@Model Template` and friends.
  - `Compose` — post-composition feature (placeholder; full facets/images
    path is the next dispatch).
  - `DesignSystem` — typography / color / component primitives
    (placeholder).
  - `AppLogging` — `os.Logger` categories and a `SecItem` Keychain
    wrapper.
- `Tests/` — `swift test` targets paralleling the source modules
  (`AuthTests`, `BlueskyTests`, `ComposeTests`, `TemplatesTests`).
- `docs/` — long-lived planning and review artifacts. See
  [`docs/README.md`](docs/README.md).

**Module-boundary rule:** only `Bluesky` imports `ATProtoKit`. Every
other module talks to Bluesky through `APIClient` and the types in
`Models`.

## Architecture spec

The source of truth for the v2 design lives on `main`. Read it with:

```sh
git show main:NEXT_STEPS_MAY_20_2026.md
```

It covers the target stack, module layout, isolation model, logging
discipline, the ATProtoKit pinning rationale, and the auth strategy
(app passwords now, OAuth later behind the same `AuthProvider`).

## CI

GitLab CI on <https://gitlab.tolbbox.com>. Both jobs (`build`, `test`)
are tagged `xcode` to route to the Mac shell runner (the `macos` tag
points at a Docker runner that can't run `xcodebuild`). `swift test
--xunit-output` produces JUnit XML that GitLab parses into per-test
pass/fail on the MR widget.

Pipelines: <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/pipelines>

## Dependencies

Pinned in `Package.swift`. Only ATProtoKit is exercised today; the rest
are wired through `DesignSystem` ahead of the UI dispatches.

| Package | Pin | Role |
| --- | --- | --- |
| [ATProtoKit](https://github.com/MasterJ93/ATProtoKit) | `0.32.5..<0.33.0` | Bluesky / atproto SDK. Imported only by `Bluesky`. |
| [Nuke](https://github.com/kean/Nuke) | `13.0.6..<14.0.0` | Image loading (unused yet). |
| [Pow](https://github.com/EmergeTools/Pow) | `from: 1.0.6` | SwiftUI transitions and delight effects (unused yet). |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | `2.4.1..<3.0.0` | Markdown rendering for bios and help (unused yet). |

## License

Personal project, no license offered.
