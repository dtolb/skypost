# Phase H — Mantis restyle — implementation plan

**Spec:** [`docs/specs/2026-05-21-phase-h-mantis-restyle-design.md`](../specs/2026-05-21-phase-h-mantis-restyle-design.md)
**Branch:** `feature/phase-h-mantis-restyle`
**Cadence:** swift-coder (Opus 4.7) subagent per task, **sequential** (kanban memory: SwiftPM races shared `.build/`).
**MR shape:** one bundled MR.

## Task graph

```
H1 (DS primitives + tests)
  → H2 (LoginView)
  → H3 (HomeView + tab wiring)   (depends on SentSessionLog from H1)
  → H4 (TemplateListView)
  → H5 (TemplateEditorView)
  → H6 (ComposeView — must run after H3 so sessionLog injection exists)
  → H7 (SettingsTabView)
  → H8 (App tint + tab order final wiring)
  → H-review (subagent reviewers, kanban update)
  → H-release (push + MR + tag)
```

Each task: implementer subagent → spec-compliance reviewer subagent → code-quality
reviewer subagent → mark done → commit. No batching of tasks across subagent
dispatches (concurrent `swift build` races `.build/`).

## H1 — DesignSystem primitives + tests

**Files touched:**
- `Sources/DesignSystem/BrandColor.swift` (new)
- `Sources/DesignSystem/BrandGradient.swift` (new)
- `Sources/DesignSystem/BrandCard.swift` (new)
- `Sources/DesignSystem/BrandSectionHeader.swift` (new)
- `Sources/DesignSystem/LeadIcon.swift` (new)
- `Sources/DesignSystem/WelcomeHero.swift` (new)
- `Sources/DesignSystem/BrandTypography.swift` (new)
- `Sources/DesignSystem/DesignSystem.swift` (drop placeholder body; replace with
  `public enum DesignSystem { public static let moduleName = "DesignSystem" }` if
  anything still references it, otherwise delete)
- `Sources/Compose/SentSessionLog.swift` (new)
- `Tests/DesignSystemTests/DesignSystemTests.swift` (new — `@Suite` per the
  existing TemplatesTests cadence)
- `Tests/ComposeTests/SentSessionLogTests.swift` (new)
- `Package.swift` — add `DesignSystemTests` target; add `SwiftUI` link by virtue
  of `import SwiftUI` in the DS sources (SPM auto-links; no manual config). DS
  target needs `import SwiftUI` so it cannot test on Linux — fine, `swift test`
  on this repo runs only on macOS via the `xcode` runner.

**TDD order (Red → Green → Refactor):**
1. Write `BrandColorTests.tintIsAntDesignBlue6()` asserting `BrandColor.tint == Color(red: 0x16/255, green: 0x77/255, blue: 0xff/255)` → fails (no BrandColor type) → implement.
2. Write `LeadIconTests.deterministicColorIsStable()` — same input string → same color. Implement via a small static palette of 6 colors keyed by `abs(hash) % palette.count`.
3. Write `WelcomeHeroAccessibilityTests.composesLabel()` — test the static
   `WelcomeHero.composeAccessibilityLabel(title:subtitle:)` helper. Implement.
4. Write `SentSessionLogTests`:
   - `appendInsertsAtFront()` — append A, append B; first entry is B.
   - `previewIsTrimmedAndSingleLine()` — body with newlines + 100 chars in →
     preview is 80 chars max, no newlines.
   - `capDropsOldest()` — append 51 entries → count == 50, last entry is the
     51st append's URI.
5. Implement `SentSessionLog` to make tests green.

**Acceptance:**
- `swift test` green (existing 82 + new DS + new SentSessionLog cases).
- `xcodebuild` green via the `App/BlueSkyTemplates.xcodeproj` shell.

## H2 — LoginView WelcomeHero restyle

**Files touched:**
- `Sources/Auth/LoginView.swift`
- `Package.swift` — Auth gains `DesignSystem` dep (Auth doesn't have it yet).

**Behavior change:** none. Visual only.

**Steps:**
1. Add `import DesignSystem`.
2. Replace plain `Text("Sign in to Bluesky")` Section header with
   `BrandSectionHeader("Sign in to Bluesky")`.
3. Add a top Section containing only a `WelcomeHero("Welcome to BlueSky
   Templates", subtitle: "Post from your saved templates.", trailing: nil)`. Hero
   uses `.listRowInsets(.init())` and `.listRowBackground(Color.clear)` so the Form
   row chrome doesn't fight the hero card edges.
4. Verify Pow shake, focus management, submit flow unchanged (no test changes —
   existing AuthTests already cover those paths).

**Acceptance:** existing AuthTests green; visual hero present in `#Preview`.

## H3 — New HomeView + tab wiring

**Files touched:**
- `Sources/BlueSkyTemplatesApp/HomeView.swift` (new)
- `Sources/BlueSkyTemplatesApp/SignedInView.swift` — add `.home` case to `AppTab`,
  insert Home tab at position 1, pass `selectedTab` binding into `HomeView`.
- `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift` — own a
  `@State private var sessionLog = SentSessionLog()` and inject via
  `.environment(sessionLog)`.
- `Tests/BlueSkyTemplatesAppTests/HomeViewActionTests.swift` (new — new test
  target).
- `Package.swift` — add `BlueSkyTemplatesAppTests` target.

**TDD order:**
1. Extract a pure `HomeAction` enum (`compose`, `newTemplate`, `templates`,
   `settings`) and a `func handle(_ action: HomeAction, selectedTab:
   inout AppTab, newSheet: inout Bool)` mutating helper. Write the test against
   that helper.
2. Implement helper.
3. Build `HomeView` around the helper; SwiftUI buttons call it.

**View structure:**
```swift
public struct HomeView: View {
    @Binding var selectedTab: AppTab
    public let session: SessionInfo
    @Environment(SentSessionLog.self) private var sessionLog: SentSessionLog?
    @Query(...) private var templates: [Template]
    @State private var newTemplateSheetPresented: Bool = false

    public var body: some View { ... }
}
```

**Acceptance:** existing tests green; `HomeViewActionTests` green; HomeView
preview renders with mock SessionInfo.

## H4 — TemplateListView LeadIcon + empty-state hero

**Files touched:**
- `Sources/Templates/TemplateListView.swift`

**Steps:**
1. `import DesignSystem`.
2. `TemplateRow` gains a leading `LeadIcon(systemName: "doc.text", tint:
   BrandColor.deterministicColor(for: template.title))`.
3. Replace `ContentUnavailableView` empty state with `WelcomeHero("No templates
   yet", subtitle: "Tap + to save your first.")` + a `BrandCard` "New template"
   button that sets `newSheetPresented = true`.

**Acceptance:** TemplatesTests green; preview renders empty + populated correctly.

## H5 — TemplateEditorView section headers

**Files touched:**
- `Sources/Templates/TemplateEditorView.swift`

**Steps:**
1. `import DesignSystem`.
2. Replace `Section("Title")` / `Section("Body")` / `Text("Hashtags")` Section
   header with `BrandSectionHeader`.
3. Hashtag footer unchanged.

**Acceptance:** TemplatesTests green; no behavior change.

## H6 — ComposeView Sent! celebration + headers + sessionLog hook

**Files touched:**
- `Sources/Compose/ComposeView.swift`

**Steps:**
1. `import DesignSystem`.
2. Replace `Section("Images")` / `Section("Link")` text headers with
   `BrandSectionHeader`.
3. `TemplatePickerLabel` gains a `LeadIcon(systemName: "doc.text", tint:
   BrandColor.tint)` at the leading edge inside the `HStack`.
4. `resultSection`'s `.sent(uri:)` branch becomes a `WelcomeHero("Posted!",
   subtitle: uri, trailing: Image(systemName: "checkmark.seal.fill"))` with the
   existing Copy-URI contextMenu attached.
5. Add `@Environment(SentSessionLog.self) private var sessionLog: SentSessionLog?`.
6. In `submit()`, immediately before `send = .sent(uri:)`, call
   `sessionLog?.append(uri: uri, body: body)`.

**Acceptance:** ComposeTests green; visual celebration in `#Preview` (preview
container also injects a `SentSessionLog`).

## H7 — SettingsTabView LeadIcon rows

**Files touched:**
- `Sources/BlueSkyTemplatesApp/SettingsTabView.swift`

**Steps:**
1. `import DesignSystem`.
2. `Section("Account")` rows become `HStack` rows with `LeadIcon(systemName:
   "person.fill", tint: BrandColor.tint)` for Handle and
   `LeadIcon(systemName: "key.fill", tint: .gray)` for DID. Preserve
   `LabeledContent`'s trailing-value behavior.
3. Sign Out gets its own Section containing a tappable row:
   `LeadIcon(systemName: "rectangle.portrait.and.arrow.right", tint: .red)` +
   "Sign out" text in `.red`. Tap → `Task { await auth.signOut() }`.

**Acceptance:** existing tests green; preview renders with a fixture session.

## H8 — App-wide tint + final SignedInView tab order

**Files touched:**
- `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift`
- `Sources/BlueSkyTemplatesApp/SignedInView.swift`

**Steps:**
1. `BlueSkyTemplatesApp.body`'s `WindowGroup { RootView()... }` gains
   `.tint(BrandColor.tint)`.
2. `SignedInView.AppTab` finalized: `case home, templates, compose, settings`.
3. Tab order in body: Home, Templates, Compose, Settings.
4. `selectedTab` default stays `.compose`.
5. Re-verify TemplateApplier hand-off `.onChange` still flips to `.compose` (no
   change needed; targeting `.compose` not `selectedTab`).

**Acceptance:** all tests green; build green; first tab visible in nav is Home but
launch lands on Compose.

## H-review — final reviewers + kanban

Dispatch:
1. **spec-compliance reviewer** (general-purpose Opus) — read the spec, diff
   `main..HEAD`, report any missing/contradicted requirements.
2. **code-quality reviewer** (general-purpose Opus) — same diff, focus on Swift
   idioms, accessibility, SwiftUI lifecycle, redundancy.

Findings:
- Critical (blocks merge): fix in a follow-up commit on the same branch.
- Cosmetic / deferrable: add to `kanban.md` under a new "Phase H" → "Deferred-cosmetic
  nits (Phase H)" section.

## H-release — push + MR + tag

1. Push `feature/phase-h-mantis-restyle` to `gitlab.tolbbox.com`.
2. Open MR against `main` titled `Phase H — Mantis design-system restyle`.
3. MR body: list of screens touched, Phase H spec link, before/after screenshots
   per screen (Dan supplies — Simulator headless on the runner Mac per F-sim
   memory).
4. Once merged, tag the release. Versioning is at Dan's discretion (kanban
   doesn't surface a current version).
