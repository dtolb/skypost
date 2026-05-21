# Phase H — Mantis restyle — design

**Date:** 2026-05-21
**Status:** Approved, ready for implementation plan
**Predecessor:** Phase G1 (Compose-first UX)
**Phase tag:** Phase H

## Problem

The app's visual language is "stock SwiftUI Forms with the default blue accent". The
TolbNet design system (Mantis) has a defined brand identity — primary tint `#1677ff`,
a 5-stop diagonal welcome gradient, 10pt continuous-radius cards, uppercase 13pt
section headers, and colored lead-icon glyphs on settings rows. None of it shows up
in the app today. The `Sources/DesignSystem` SPM target is a placeholder.

The reference is `mantis/design-system/ui_kits/ios/` — itself a web mock of a native
iOS app whose real deliverable is the **source-verified decisions table** in its
README (primary tint, 5-stop gradient, 10pt iOS continuous card radius, SF Pro stack).
The mock's *content* (balance, transactions, wallet) is demo material, not features to
port — this is a Bluesky-templates app.

## Goals

- Apply Mantis brand identity across all five existing screens (`LoginView`,
  `TemplateListView`, `TemplateEditorView`, `ComposeView`, `SettingsTabView`).
- Add a new **Home** tab with a gradient welcome hero, 4-action quick grid, and a
  "This session" sent-posts log driven by a new in-memory `SentSessionLog`.
- Grow `Sources/DesignSystem` from a placeholder into a small primitive library
  (`BrandColor`, `BrandGradient`, `BrandCard`, `BrandSectionHeader`, `LeadIcon`,
  `WelcomeHero`, `BrandTypography`). The architecture spec's "don't pre-build a kit
  — grow only when the same styling gets copy-pasted 3+ times" rule is satisfied:
  every primitive is consumed in 3+ screens.
- Preserve every existing behavior — Pow shake/spray, focus management, `.task(id:)`
  flows, TemplateApplier hand-off, link-card flow, image picker, accessibility.
- Keep the Phase G1 "Compose-first" landing: `selectedTab` still defaults to
  `.compose`. Home is browsable from tab position 1 but isn't the cold-launch screen.

## Non-goals

- No backend / API surface changes. No new `APIClient` methods. No SwiftData
  migration. The Home tab does **not** fetch the author feed.
- No OAuth migration (deferred per architecture §7.3 trigger).
- No motion-design changes — Pow effects retained as-is.
- No dark-mode-specific token work beyond what SwiftUI already provides
  (`systemGroupedBackground`, `secondary`/`tertiary` foreground styles). Mantis
  ships a light-mode-first identity; dark-mode brand work is a future phase.
- No XCUITest harness work (deferred per kanban Phase G note).
- No icon catalog rework (existing SF Symbols stay).
- No tab-order change beyond inserting Home in position 1.

## Architecture changes

### New module surface — `Sources/DesignSystem`

The module today exports a single `enum DesignSystem { static let moduleName = "DesignSystem" }`.
Phase H grows it into a small primitive library. All primitives are pure SwiftUI
value types or `View` structs with no external state.

| Primitive | Purpose | Consumed by |
|-----------|---------|-------------|
| `BrandColor` | `tint = #1677ff`, `incomeGreen = #52c41a`, `expenseRed = #f5222d`, hex-literal constants verified against Mantis tokens | App tint, hero, success badges |
| `BrandGradient.welcome` | 5-stop diagonal `LinearGradient` (lighter→light→main→dark→darker, 250.38°) matching Mantis web `WelcomeBanner` | `WelcomeHero` |
| `BrandCard<Content>` | 10pt continuous-radius surface, white-on-`systemGroupedBackground`, optional Mantis primaryButton shadow | Home, hero CTAs |
| `BrandSectionHeader(_:)` | Uppercase 13pt, tracking 0.08em, secondary foreground; intended for `Section { ... } header: { BrandSectionHeader("Title") }` | All forms |
| `LeadIcon(systemName:tint:)` | 30pt rounded-square colored glyph, SF Symbol body | Settings, picker, template rows |
| `WelcomeHero(title:subtitle:trailing:)` | Gradient hero card, `padding 20`, `radius 16`, `primaryButton` shadow | Login, Compose Sent, Templates empty, Home |
| `BrandTypography.largeTitleStyle()` | 34pt / 700 / tracking -0.9 — viewmodifier; iOS large-title default is close but tracking differs | Hero subtitle, Home greeting |

The DS module gets a new `DesignSystemTests` target with tests for derived state only:

- `BrandColor.tint` resolves to `0x1677ff` in linear RGB
- `LeadIcon.deterministicColor(for:)` returns the same color for the same input string and
  cycles through a known palette
- `WelcomeHero` exposes its accessibility label (`title + ". " + subtitle`)

Pure-visual rendering is not snapshot-tested (project convention; no snapshot dep).

### New runtime piece — `SentSessionLog`

Lives in `Sources/Compose` (the producer module — keeps the model close to where
appends happen; consumer `HomeView` imports `Compose`). An `@Observable final class`
with:

```swift
@Observable
public final class SentSessionLog {
    public struct Entry: Hashable, Sendable {
        public let uri: String
        public let createdAt: Date
        public let preview: String   // first 80 chars of the body, single-line
    }
    public private(set) var entries: [Entry] = []
    public static let cap = 50

    public init() {}
    public func append(uri: String, body: String, now: Date = .now) { ... }
}
```

- `ComposeView.submit` calls `sessionLog.append(uri:body:)` on success, just before the
  existing auto-clear path.
- `HomeView` reads `sessionLog.entries` (already-reversed: most recent first).
- Cap at 50 (`cap`). On overflow, drop the oldest. Newest at index 0.
- In-memory only — wiped on app termination by design. Persisting "sent posts" is
  out of scope (and largely redundant with the user's PDS).

`SentSessionLog` is wired into `BlueSkyTemplatesApp` as a long-lived `@State` and
injected via `.environment(sessionLog)`.

### New screen — `HomeView`

Lives in `Sources/BlueSkyTemplatesApp/HomeView.swift`. Reads `SessionInfo` from
parent, `[Template]` via `@Query`, `SentSessionLog` from environment.

Structure (top-to-bottom):

1. `WelcomeHero("Welcome back", subtitle: "@<handle>", trailing: count chip)` — the
   trailing chip reads `"\(templates.count) templates"`, glass-pill rounded.
2. **Quick actions** — 4-cell `LazyVGrid` of `BrandCard`-wrapped buttons:
   *Compose* (flips `selectedTab` to `.compose`),
   *New template* (presents `TemplateEditorView(mode: .new)` sheet),
   *Templates* (flips to `.templates`),
   *Settings* (flips to `.settings`).
3. **This session** — `BrandSectionHeader("Sent this session")` + grouped `List` of
   `SentSessionLog.Entry` rows. Each row: SF Symbol checkmark.seal.fill in
   `BrandColor.tint`, preview text, relative time. Tap → copy URI to pasteboard
   with a brief inline confirmation. Empty state: subdued single-line "Nothing
   sent yet — go post something."

`HomeView` does **not** own the tab selection. It receives a `@Binding<AppTab>` from
`SignedInView` so its quick-action buttons can flip the parent's `selectedTab`.

### `SignedInView` changes

```swift
private enum AppTab: Hashable {
    case home, templates, compose, settings   // home added at front
}

@State private var selectedTab: AppTab = .compose  // unchanged default — G1 win preserved
```

Tab order in the `TabView` body: Home, Templates, Compose, Settings.
TemplateApplier hand-off `.onChange` continues to flip to `.compose`.

### App tint

`BlueSkyTemplatesApp.body`'s `WindowGroup` content gains `.tint(BrandColor.tint)`,
which propagates to every `Color.accentColor` consumer (`.borderedProminent`
buttons, links, picker chevrons). No per-view `.tint` overrides needed.

## Per-screen behavior (visual deltas only; no logic changes)

### LoginView

- Add `WelcomeHero("Welcome to BlueSky Templates", subtitle: "Post from your saved
  templates.")` as the first row of the Form (or above the Form in a `VStack`,
  TBD by implementer — Form-row hero is cleaner if it renders right).
- `Section("Sign in to Bluesky")` header replaced with `BrandSectionHeader`.
- Sign-in `.borderedProminent` button inherits the new `BrandColor.tint` via the
  app-wide tint — no explicit override.
- Pow shake + haptic preserved.

### TemplateListView

- Each row gains a `LeadIcon(systemName: "doc.text", tint: BrandColor.deterministicColor(for: template.title))`.
- Empty state — replace `ContentUnavailableView` with a `WelcomeHero("No templates
  yet", subtitle: "Tap + to save your first.")` and a `BrandCard` containing a
  prominent "New template" button that triggers the same `newSheetPresented = true`.
- Row tap-to-apply, trailing swipe Edit + Delete, and context menu Edit/Delete all
  preserved.

### TemplateEditorView

- `Section("Title")`, `Section("Body")`, `Section { ... } header: { Text("Hashtags") }`
  switch to `BrandSectionHeader`.
- Hashtag footer text unchanged.
- Save / Cancel toolbar unchanged.

### ComposeView

- `Section { TemplatePickerLabel(...) }` — picker row gets a `LeadIcon(systemName:
  "doc.text", tint: BrandColor.tint)` leading the "Template" label.
- All other section headers (`"Images"`, `"Link"`) switch to `BrandSectionHeader`.
- `.sent(uri:)` `resultSection` becomes:
  ```swift
  WelcomeHero(
      title: "Posted!",
      subtitle: uri,
      trailing: Image(systemName: "checkmark.seal.fill")
  )
  .contextMenu { Button { copy(uri) } label: { Label("Copy URI", ...) } }
  ```
- `.failed(message:)` stays a `Label(...)` (errors don't get the celebration
  treatment).
- `submit()` adds `sessionLog.append(uri: uri, body: body)` immediately before
  `send = .sent(uri:)`.

### SettingsTabView

- `Section("Account")` gains `LeadIcon` rows: `person.fill` (handle), `key.fill`
  (DID).
- Section header → `BrandSectionHeader`.
- Sign Out gets its own `Section { ... }` with a `LeadIcon(systemName:
  "rectangle.portrait.and.arrow.right", tint: .red)` row whose tap fires
  `Task { await auth.signOut() }`.

## Testing strategy

Per architecture §6.2 — Swift Testing only, no snapshot framework.

| Surface | TDD discipline | Test home |
|---------|----------------|-----------|
| `BrandColor` hex constants | Smoke equality | `DesignSystemTests` (new target) |
| `LeadIcon.deterministicColor(for:)` | Property: same input → same output; palette membership | `DesignSystemTests` |
| `WelcomeHero` accessibility label composition | Single assertion | `DesignSystemTests` |
| `SentSessionLog` append / cap / ordering / preview-truncation | Full TDD | `ComposeTests` (lives in Compose module) |
| `HomeView` derived state | Action-tap intent surfacing via a closure injection (`onAction: (HomeAction) -> Void`) so the test doesn't need a SwiftUI host | New `BlueSkyTemplatesAppTests` target |
| Existing 82 tests | Must stay green | `swift test --xunit-output` |

Pure visual changes (hero gradient stops, card radius, section-header styling) are
**not** unit-tested. The implementer must verify visually in the iOS simulator and
attach a screenshot to the MR per Phase F's UI-verification standard.

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Mantis 5-stop gradient looks heavy on small screens (LoginView hero overwhelms the form) | Cap hero `padding 20`, hero height ~88pt minimum; implementer eyeballs and tunes |
| `BrandSectionHeader` breaks `Form`'s default uppercase grouped-form rendering on iOS 26 | iOS already uppercases plain-text Section headers in grouped style; passing `BrandSectionHeader` should layer correctly. If conflict, implementer adds `.textCase(nil)` to the Section to disarm the system uppercase |
| Reorder + insert-Home creates Phase-G1 regression (Compose no longer feels "first") | `selectedTab = .compose` stays the default. Verified during H8. |
| Tinting at the WindowGroup affects `.foregroundStyle(.red)` errors / Pow visuals | `.tint` only changes `Color.accentColor`; explicit `.red` / `.green` / system-tint usages are unaffected. Pow's `.tint` consumer in the spray uses the new brand blue — that's intended (brand-on celebration). |
| `SentSessionLog` retained across sign-out + sign-in cycles in the same process | Acceptable — entries belong to the *process*, not the *session*. If a future user complains, gate `entries` reset on `AuthService.signOut`. |
| Adding a fourth tab pushes label glyphs tighter; iOS abbreviates at 4-tab density | Acceptable; HIG supports up to 5 tabs. Labels stay verbatim ("Home" / "Templates" / "Compose" / "Settings"). |

## Open questions

None at spec-approval time. Implementer decisions:

- Exact hero copy on the empty-state Templates card.
- Whether Compose's `Sent!` hero auto-clears after 2s (current behavior) or stays
  until the user taps elsewhere. Default: keep the 2s auto-clear — no behavior change.

## Out-of-band

- Branch: `feature/phase-h-mantis-restyle`
- MR: one bundled MR against `main` (per user direction "one big MR")
- Release: tagged after MR merge (Dan decides version)
