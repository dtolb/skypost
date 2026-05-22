# Phase J - iCloud template storage, exchange, and App Intents

> **Date:** 2026-05-22
> **Branch:** `main` working tree
> **Goal:** Move saved templates from local-only SwiftData to private iCloud-backed SwiftData, add native JSON import/export for sharing, and expose one narrow App Intent for template creation.

## Plan

1. Make the `Template` model CloudKit-compatible.
   - Remove the unsupported SwiftData unique constraint.
   - Add defaults for nonoptional stored properties.
   - Preserve stable `UUID` and `updatedAt` values for imports.

2. Add explicit template storage configuration.
   - Use `TemplateStorage` for the `Template` schema.
   - Use private CloudKit container `iCloud.com.dtolb.BlueSkyTemplates`.
   - Keep an in-memory, non-CloudKit container factory for tests and previews.

3. Add template exchange primitives.
   - Use a versioned JSON document for single templates.
   - Support archive decoding for multiple templates.
   - Upsert by stable template UUID because CloudKit-backed SwiftData cannot enforce uniqueness.
   - Clean up duplicate local rows found during import.

4. Add minimal Templates UI.
   - Import one or more `.json` files from the Templates toolbar.
   - Export a single template from the row context menu.
   - Keep create, edit, delete, and template-apply behavior unchanged.

5. Wire app capabilities.
   - Replace the default `modelContainer(for:)` with the explicit CloudKit-backed container.
   - Fall back to a local SwiftData container if CloudKit-backed initialization fails.
   - Add CloudKit iCloud entitlements and `remote-notification` background mode.

6. Add the smallest useful App Intents surface.
   - Add `CreateTemplateIntent`.
   - Add app-target `AppShortcutsProvider` so metadata is emitted for Shortcuts.
   - Keep intent logic thin and routed through the same Templates storage primitives.

7. Fix the dark-mode surface regression found after the iCloud work.
   - Replace hard-coded white card/list fills with `BrandColor.cardBackground`.
   - Make `LeadIcon` color-scheme-aware so dark mode no longer keeps light-mode icon glyph treatment on normal app surfaces.
   - Keep `BrandColor.pageBackground` for full-screen backgrounds.
   - Add DesignSystem tests so the card and icon surfaces remain centralized.

8. Verify through the existing CI path.
   - `swift test`
   - `swift test --xunit-output build/junit.xml`
   - `cd App && xcodegen generate`
   - `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug`
   - XcodeBuildMCP `build_run_sim`

## Shipped

- `Template` is CloudKit-compatible and keeps stable import identity.
- `TemplateStorage` centralizes CloudKit and in-memory SwiftData containers.
- `TemplateExchange` provides JSON encode, decode, archive decode, and UUID upsert.
- `TemplateListView` imports and exports template JSON through native SwiftUI file APIs.
- `AppRoot` uses `TemplateStorage.makeCloudContainer()` and logs a fallback if local storage is needed.
- App entitlements include CloudKit services and `iCloud.com.dtolb.BlueSkyTemplates`.
- XcodeGen uses automatic Apple Development signing for team `49LQ789275`; iCloud entitlements cannot use "Sign to Run Locally".
- `Info.plist` and XcodeGen config include `UIBackgroundModes.remote-notification`.
- `CreateTemplateIntent` and an app shortcut expose template creation to Shortcuts.
- Card/list surfaces now use dynamic `BrandColor.cardBackground` instead of hard-coded light-only white fills.
- `LeadIcon` now uses solid tint + white glyphs in light mode and a softer tinted surface + tint glyphs in dark mode.

## Verification

- `swift test`: passed, 111 tests.
- `swift test --xunit-output build/junit.xml`: passed, produced `build/junit-swift-testing.xml`.
- `cd App && xcodegen generate`: passed.
- `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug`: passed.
- XcodeBuildMCP `build_run_sim`: passed and launched on iPhone 17 simulator.
- XcodeBuildMCP dark-mode simulator pass: launched under dark appearance and captured a screenshot for visual smoke verification.

## Caveats

- Device and production iCloud sync require the Apple Developer CloudKit container/provisioning setup for `iCloud.com.dtolb.BlueSkyTemplates`.
- The secondary `github/main` remote is behind the GitLab `origin/main`; this repo tracks `origin/main`.
- The iOS build still reports existing `LiveExternalLinkResolver` Sendable warnings. They are unrelated to this phase.
