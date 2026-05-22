# Phase I — Cleanup sprint — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Knock down the kanban tail accumulated through Phases A–H — plan-numbered review items (#8/#10/#15), cross-cutting DS/UX nits, and per-phase carry-forward cosmetic items — in one focused sprint with no user-visible behavior change.

**Architecture:** Single feature branch `feature/phase-i-cleanup` off `main`, one MR (Phase H pattern, no stacking). Twelve sequential `swift-coder` (Opus 4.7) dispatches; each task gets implementer → spec-compliance reviewer → code-quality reviewer → kanban tick. Concurrent `swift build` races `.build/`, so dispatches are non-negotiably sequential.

**Tech Stack:** Swift 6.2 (`swiftLanguageModes: [.v6]`), SwiftPM workspace, SwiftUI views, Swift Testing (`@Test` / `#expect`), `xcodebuild` against iPhone 17 simulator, GitLab CI `xcode` runner with JUnit reports.

**Spec:** [`docs/specs/2026-05-21-phase-i-cleanup-design.md`](../specs/2026-05-21-phase-i-cleanup-design.md)

---

## Task graph

```
I.A1 (rename App struct)
  → I.A2 (@MainActor justification comments)
  → I.A3 (semantic-color migration — adds BrandColor.destructive + .error)
  → I.B1 (drop LeadIcon .accessibilityHidden call-sites)
  → I.B2 (BrandColor.pageBackground primitive)
  → I.B3 (TemplateListView delete-while-edited guard)
  → I.B4 (HomeView "New template" a11y label)
  → I.C1 (Phase B/D ComposeView consolidation)
  → I.C2 (Phase C ImageProcessor cleanup)
  → I.C3 (Phase E/F test polish)
  → I.C4 (Phase F ComposeView link-state readability)
  → I.C5 (Phase G1 preview/type polish)
  → I-review (whole-phase reviewer subagents + kanban update)
  → I-release (push branch + open MR + tag)
```

**Baseline before I.A1:** 95/95 tests, `xcodebuild` against iPhone 17 sim green, `main` at `206ea8d` + spec commit `fb79aaa`.

**Branch setup (do once before I.A1):**

- [ ] **Cut branch from main:** `git checkout -b feature/phase-i-cleanup`

---

## I.A1 — Rename `BlueSkyTemplatesApp` struct → `AppRoot`

**Why:** Plan #8. The struct shadows the containing module name (`BlueSkyTemplatesApp`), making `import BlueSkyTemplatesApp` followed by `BlueSkyTemplatesApp(...)` ambiguous to read. The struct is internal-shape (the real `@main` lives on the executable shim at `App/Sources/AppMain.swift`); renaming costs little.

**Files:**
- Modify: `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift` (rename struct; also rename file → `Sources/BlueSkyTemplatesApp/AppRoot.swift`)
- Modify: `App/Sources/AppMain.swift` (or whatever the `@main` shim is — search and update)
- Search-and-replace any references in `Sources/`, `Tests/`, `Sources/Compose/ComposeView.swift:50` (comment), `Sources/BlueSkyTemplatesApp/SignedInView.swift:14` (comment), `Sources/Bluesky/EnvironmentKeys.swift:16,31` (comments)

**Behavior change:** none. Pure rename.

**TDD applicability:** none — rename verified by `swift test` + `xcodebuild` staying green.

- [ ] **Step 1 — Enumerate references**

  ```bash
  grep -rn "BlueSkyTemplatesApp" Sources/ Tests/ App/ | grep -v "// " | grep -v "import BlueSkyTemplatesApp"
  ```

  Expected hits: struct definition + the `@main` shim + ~4 comments. The string `BlueSkyTemplatesApp` *as a module name* (in `import`, `Package.swift`, target/product names) stays — do NOT rename the module.

- [ ] **Step 2 — Rename the struct in `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift`**

  Change:
  ```swift
  public struct BlueSkyTemplatesApp: App {
  ```
  to:
  ```swift
  public struct AppRoot: App {
  ```

- [ ] **Step 3 — Rename the file**

  ```bash
  git mv Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift Sources/BlueSkyTemplatesApp/AppRoot.swift
  ```

- [ ] **Step 4 — Update the `@main` shim**

  Read `App/Sources/AppMain.swift` (or `App/Sources/<shim>.swift`). It will look something like:
  ```swift
  @main
  struct AppShim {
      static func main() { BlueSkyTemplatesApp.main() }
  }
  ```
  Update to `AppRoot.main()`.

- [ ] **Step 5 — Update prose-comment references**

  In `Sources/Compose/ComposeView.swift:50`, `Sources/BlueSkyTemplatesApp/SignedInView.swift:14`, `Sources/Bluesky/EnvironmentKeys.swift:16,31`, any other prose-comment hits from Step 1: replace `BlueSkyTemplatesApp` (when referring to the struct) with `AppRoot`. Leave module-name mentions ("the `BlueSkyTemplatesApp` module") alone.

- [ ] **Step 6 — Verify build + tests**

  ```bash
  swift build && swift test
  ```
  Expected: 95/95 tests pass, no warnings.

- [ ] **Step 7 — Verify Xcode build**

  ```bash
  xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: BUILD SUCCEEDED.

- [ ] **Step 8 — Commit**

  ```bash
  git add -A
  git commit -m "$(cat <<'EOF'
  refactor(app): rename BlueSkyTemplatesApp struct → AppRoot (I.A1, plan #8)

  Disambiguates @main-bearing struct from the containing module name.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.A2 — `@MainActor` justification comments on `AuthService` + `AppRouter`

**Why:** Plan #10. Both classes carry `@MainActor` annotations. `Package.swift` shows `swiftLanguageModes: [.v6]` but no `defaultIsolation` setting, so the project is *not* opted into Swift 6 main-actor-by-default. The annotations are therefore **load-bearing** (without them the `@Observable` final-class would default to non-isolated, breaking SwiftUI's main-thread observation contract). The plan-#10 ask is "drop OR document why kept"; the answer is "document why kept" — once. Future-me reading the code shouldn't have to re-derive this.

**Files:**
- Modify: `Sources/Auth/AuthService.swift:12`
- Modify: `Sources/BlueSkyTemplatesApp/AppRouter.swift:9`

**Behavior change:** none. Comment-only.

**TDD applicability:** none.

- [ ] **Step 1 — Add comment above `@MainActor` in `AuthService.swift:12`**

  Insert above the `@MainActor` line:
  ```swift
  // `@MainActor` is load-bearing: SwiftUI observes `@Observable` mutations
  // from MainActor, and this class isn't opted into Swift 6's
  // main-actor-by-default (no `defaultIsolation: MainActor.self` in
  // Package.swift). Keep the annotation explicit.
  @MainActor
  @Observable
  public final class AuthService {
  ```

- [ ] **Step 2 — Same treatment for `AppRouter.swift:9`**

  Match the comment text/style; the rationale is identical.

- [ ] **Step 3 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 95/95 tests pass, BUILD SUCCEEDED.

- [ ] **Step 4 — Commit**

  ```bash
  git add Sources/Auth/AuthService.swift Sources/BlueSkyTemplatesApp/AppRouter.swift
  git commit -m "$(cat <<'EOF'
  docs(auth,app): document load-bearing @MainActor annotations (I.A2, plan #10)

  Package.swift is Swift 6 language mode but does NOT set
  defaultIsolation: MainActor.self, so the @MainActor annotations on
  AuthService and AppRouter are required (not redundant) for
  @Observable SwiftUI binding to land on the right actor.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.A3 — Semantic-color consumer migration (`.red` literals → `BrandColor`)

**Why:** Plan #15. Phase H landed `BrandColor.tint/incomeGreen/expenseRed` primitives but didn't migrate the 5 consumer call-sites that still use literal `.red`. Some sites are *destructive UI* (sign-out icon/label) and some are *error messaging* (auth/post failures, character-overflow warning). They want different semantic names. Add two new role colors and migrate.

**Files (read first):**
- `Sources/Auth/LoginView.swift:132` — inline error row foreground
- `Sources/Compose/ComposeView.swift:131` — over-character-count counter `AnyShapeStyle`
- `Sources/Compose/ComposeView.swift:159` — graceful api-nil error label
- `Sources/Compose/ComposeView.swift:428` — send-failure error label
- `Sources/BlueSkyTemplatesApp/SettingsTabView.swift:59` — sign-out `LeadIcon` tint
- `Sources/BlueSkyTemplatesApp/SettingsTabView.swift:63` — "Sign out" label foreground
- `Sources/BlueSkyTemplatesApp/RootView.swift:56` — restore-error display

**Files modified:**
- `Sources/DesignSystem/BrandColor.swift` (add `.destructive` + `.error` static properties)
- `Tests/DesignSystemTests/DesignSystemTests.swift` (add assertions on the two new properties)
- The 5 consumer files above

**Behavior change:** Visual only — both new role colors map to the existing Mantis dust-red-6 RGB tuple (`245/255, 34/255, 45/255`), so on screen this is a *no-change* from today's `.red` (which renders as system red, not Mantis red — slight shift). Treat the visual delta as the *intended* outcome.

**Mapping decided in this plan (consumer review):**
| Site | Role | New token |
|------|------|-----------|
| `LoginView:132` | error message | `BrandColor.error` |
| `ComposeView:131` | overflow warning | `BrandColor.error` |
| `ComposeView:159` | error message | `BrandColor.error` |
| `ComposeView:428` | error message | `BrandColor.error` |
| `SettingsTabView:59` | destructive action icon | `BrandColor.destructive` |
| `SettingsTabView:63` | destructive action label | `BrandColor.destructive` |
| `RootView:56` | restore error | `BrandColor.error` |

**TDD applicability:** YES for the new public properties. Write tests first.

- [ ] **Step 1 — Failing tests**

  Open `Tests/DesignSystemTests/DesignSystemTests.swift` and add to the existing BrandColor suite (or add a new `@Suite`):

  ```swift
  @Test func destructiveMatchesDustRed6() {
      // BrandColor.destructive == Mantis dust-red-6 (#f5222d)
      #expect(BrandColor._destructiveRGB == BrandColor._expenseRedRGB)
  }

  @Test func errorMatchesDustRed6() {
      // BrandColor.error == Mantis dust-red-6 today. May diverge later
      // if we adopt a softer error-vs-destructive distinction; the tuple
      // assertion guards intent.
      #expect(BrandColor._errorRGB == BrandColor._expenseRedRGB)
  }
  ```

- [ ] **Step 2 — Run tests; expect failure**

  ```bash
  swift test --filter DesignSystemTests
  ```
  Expected: compile error — `_destructiveRGB` / `_errorRGB` don't exist.

- [ ] **Step 3 — Add the new static properties to `BrandColor.swift`**

  Append below `expenseRed` declaration (around line 30):

  ```swift
  /// Destructive-action role color. Sign-out, delete, irreversible affordances.
  /// Same hue as `expenseRed` today; named separately so a future fork doesn't
  /// require ripping out call-sites.
  public static let destructive: Color = Color(
      red: _destructiveRGB.red,
      green: _destructiveRGB.green,
      blue: _destructiveRGB.blue
  )

  /// Error-message role color. Inline error rows, failure copy.
  /// Same hue as `expenseRed` today; named separately so a future softer
  /// error tint can land without rewriting consumers.
  public static let error: Color = Color(
      red: _errorRGB.red,
      green: _errorRGB.green,
      blue: _errorRGB.blue
  )
  ```

  And add the internal tuples below `_expenseRedRGB`:

  ```swift
  internal static let _destructiveRGB: (red: Double, green: Double, blue: Double) =
      _expenseRedRGB

  internal static let _errorRGB: (red: Double, green: Double, blue: Double) =
      _expenseRedRGB
  ```

- [ ] **Step 4 — Run tests; expect pass**

  ```bash
  swift test --filter DesignSystemTests
  ```
  Expected: green (count = previous + 2).

- [ ] **Step 5 — Migrate the consumer sites per the mapping table above**

  For each row in the mapping:

  - In `LoginView.swift:132`, `ComposeView.swift:159,428`, `RootView.swift:56`: change `.foregroundStyle(.red)` → `.foregroundStyle(BrandColor.error)`.
  - In `ComposeView.swift:131`: change `AnyShapeStyle(.red)` → `AnyShapeStyle(BrandColor.error)`.
  - In `SettingsTabView.swift:59`: change `tint: .red` → `tint: BrandColor.destructive`.
  - In `SettingsTabView.swift:63`: change `.foregroundStyle(.red)` → `.foregroundStyle(BrandColor.destructive)`.

  Add `import DesignSystem` to any file that doesn't already have it. `LoginView` (Auth module) gained the dep in Phase H2; verify via `grep "import DesignSystem" Sources/Auth/LoginView.swift`. `RootView` (`BlueSkyTemplatesApp` module) also already imports DS by virtue of using `BrandColor.tint` in WindowGroup — verify.

- [ ] **Step 6 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 97/97 tests pass (+2 from Step 1), BUILD SUCCEEDED.

- [ ] **Step 7 — Commit**

  ```bash
  git add -A
  git commit -m "$(cat <<'EOF'
  feat(design-system): semantic role colors + consumer migration (I.A3, plan #15)

  Adds BrandColor.destructive and BrandColor.error. Both map to the
  existing Mantis dust-red-6 tuple today; named separately so future
  fork (softer error tint, distinct destructive shade) lands without
  rewriting consumers.

  Migrates 7 call-sites previously using .red:
  - Auth/LoginView, Compose/ComposeView (×3), App/RootView    → .error
  - App/SettingsTabView icon + label                          → .destructive

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.B1 — Drop `LeadIcon(...).accessibilityHidden(true)` call-sites

**Why:** `LeadIcon.swift:28` already applies `.accessibilityHidden(true)` internally. Three call-sites in `SettingsTabView` and one in `ComposeView` repeat it. Pick one direction across the codebase: **keep internal, drop call-sites.** That keeps the primitive self-contained.

**Files:**
- Modify: `Sources/BlueSkyTemplatesApp/SettingsTabView.swift:31, 39, 61`
- Modify: `Sources/Compose/ComposeView.swift:745` (verify line — search for the call site)

**Behavior change:** none. `LeadIcon` already hides itself from VoiceOver.

**TDD applicability:** none.

- [ ] **Step 1 — Drop in `SettingsTabView.swift`**

  At each of the three sites (lines 31, 39, 61 in current code), delete the `.accessibilityHidden(true)` line that immediately follows `LeadIcon(...)`.

- [ ] **Step 2 — Drop in `ComposeView.swift`**

  ```bash
  grep -n "accessibilityHidden(true)" Sources/Compose/ComposeView.swift
  ```
  At the line immediately following the `LeadIcon(...)` constructor call, delete `.accessibilityHidden(true)`.

- [ ] **Step 3 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 97/97 tests pass, BUILD SUCCEEDED.

- [ ] **Step 4 — Commit**

  ```bash
  git add Sources/BlueSkyTemplatesApp/SettingsTabView.swift Sources/Compose/ComposeView.swift
  git commit -m "$(cat <<'EOF'
  refactor(ds): drop redundant LeadIcon.accessibilityHidden call-sites (I.B1)

  LeadIcon.swift:28 already applies .accessibilityHidden(true) internally.
  Call-site repeats in SettingsTabView (×3) and ComposeView (×1) removed.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.B2 — Promote `Color(white: 0.95)` macOS-fallback to `BrandColor.pageBackground`

**Why:** The grouped-form-style page background is duplicated in `HomeView.swift:217-223` (static var) and `TemplateListView.swift:116-122` (instance var), with subtly inconsistent visibility scopes. Promote to a DS primitive before a third site lands.

**Files:**
- Modify: `Sources/DesignSystem/BrandColor.swift` (add `pageBackground` static property)
- Modify: `Tests/DesignSystemTests/DesignSystemTests.swift` (no asserting on UIColor — light coverage)
- Modify: `Sources/BlueSkyTemplatesApp/HomeView.swift:78, 217-223`
- Modify: `Sources/Templates/TemplateListView.swift:47, 116-122`

**Behavior change:** none. Same color resolution on both platforms.

**TDD applicability:** light — a test that the property exists (compile-time) plus a smoke `#expect(BrandColor.pageBackground != Color.clear)` is the most that's worth writing without UIColor inspection.

- [ ] **Step 1 — Failing test (smoke)**

  Add to `DesignSystemTests`:
  ```swift
  @Test func pageBackgroundIsNonClear() {
      // Smoke: BrandColor.pageBackground resolves to *some* color,
      // not Color.clear. Cross-platform value (UIKit vs macOS fallback).
      #expect(BrandColor.pageBackground != Color.clear)
  }
  ```

- [ ] **Step 2 — Run; expect compile failure**

  ```bash
  swift test --filter DesignSystemTests
  ```
  Expected: `pageBackground` undefined.

- [ ] **Step 3 — Add to `BrandColor.swift`**

  Append:
  ```swift
  /// Grouped-form-style page background. On iOS this is the dynamic
  /// `systemGroupedBackground`; on macOS we approximate with a light
  /// gray that contrasts with `Color.white` card surfaces.
  public static var pageBackground: Color {
      #if canImport(UIKit)
      Color(uiColor: .systemGroupedBackground)
      #else
      Color(white: 0.95)
      #endif
  }
  ```

  Note: `import UIKit` may need to be conditionally imported inside `BrandColor.swift`:
  ```swift
  #if canImport(UIKit)
  import UIKit
  #endif
  ```
  (place after `import SwiftUI` at top of file.)

- [ ] **Step 4 — Run; expect pass**

  ```bash
  swift test --filter DesignSystemTests
  ```
  Expected: 98/98.

- [ ] **Step 5 — Migrate `HomeView.swift`**

  Delete the static `pageBackground` declaration (lines 217-223). Replace the call site at line 78:
  ```swift
  .background(Self.pageBackground)
  ```
  with:
  ```swift
  .background(BrandColor.pageBackground)
  ```

- [ ] **Step 6 — Migrate `TemplateListView.swift`**

  Delete the instance `pageBackground` declaration (lines 116-122). Replace the call site at line 47:
  ```swift
  .background(pageBackground)
  ```
  with:
  ```swift
  .background(BrandColor.pageBackground)
  ```

- [ ] **Step 7 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED.

- [ ] **Step 8 — Commit**

  ```bash
  git add -A
  git commit -m "$(cat <<'EOF'
  feat(design-system): promote pageBackground to BrandColor primitive (I.B2)

  Consolidates duplicated Color(white: 0.95) macOS fallback from
  HomeView and TemplateListView into BrandColor.pageBackground.
  Single source of truth for grouped-form page bg.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.B3 — `TemplateListView.delete(_:)` clears `navigationTarget` on self-delete

**Why:** G1.4 carry-forward. If `navigationTarget == template` when `delete(_:)` runs, the editor remains pushed against a deleted SwiftData model. Narrow race (deletion-while-edited), but a 2-line defensive guard closes it.

**Files:**
- Modify: `Sources/Templates/TemplateListView.swift:108-111`

**Behavior change:** narrow UI race — does not affect golden path.

**TDD applicability:** the deletion path is plain SwiftData; the navigation race needs a SwiftUI host. Skip a unit test; verify by reasoning + manual sim run later.

- [ ] **Step 1 — Update `delete(_:)`**

  Replace lines 108-111:
  ```swift
  private func delete(_ template: Template) {
      modelContext.delete(template)
      try? modelContext.save()
  }
  ```
  with:
  ```swift
  private func delete(_ template: Template) {
      // If the editor was pushed against this template, dismiss it before
      // the model disappears under the destination view.
      if navigationTarget == template {
          navigationTarget = nil
      }
      modelContext.delete(template)
      try? modelContext.save()
  }
  ```

- [ ] **Step 2 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED.

- [ ] **Step 3 — Commit**

  ```bash
  git add Sources/Templates/TemplateListView.swift
  git commit -m "$(cat <<'EOF'
  fix(templates): clear navigationTarget on self-delete (I.B3, G1.4 nit)

  Narrow UI race: deleting a template while its editor was pushed left
  the destination view rendering against a detached SwiftData model.
  Guard nils out navigationTarget before the modelContext.delete call.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.B4 — HomeView quick-action a11y label "New" → "New template"

**Why:** H3 nit. `HomeView.swift:140`'s `.accessibilityLabel(title)` passes the visible title verbatim. The "+" cell's title is "New" (4 chars, fits the 4-column grid) — but VoiceOver reading just "New" loses context. Override the a11y label specifically for that cell.

**Files:**
- Modify: `Sources/BlueSkyTemplatesApp/HomeView.swift:121-141`

**Behavior change:** a11y string only.

**TDD applicability:** none for the cell label; could in theory snapshot the rendered AX tree but skip.

- [ ] **Step 1 — Update `actionCell` signature + body**

  Replace the `actionCell` function (lines 121-141) so the a11y label is an explicit parameter:
  ```swift
  private func actionCell(
      systemName: String,
      title: String,
      action: HomeAction,
      accessibilityLabel: String? = nil
  ) -> some View {
      Button {
          handleHomeAction(
              action,
              selectedTab: &selectedTab,
              newTemplateSheetPresented: &newTemplateSheetPresented
          )
      } label: {
          VStack(spacing: 8) {
              LeadIcon(systemName: systemName, tint: BrandColor.tint)
              Text(title)
                  .font(.caption)
                  .foregroundStyle(.primary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(Color.white, in: .rect(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(accessibilityLabel ?? title)
  }
  ```

- [ ] **Step 2 — Pass explicit label for the "+" cell only**

  In the `quickActions` grid (around line 114), update the New cell to:
  ```swift
  actionCell(systemName: "plus", title: "New", action: .newTemplate, accessibilityLabel: "New template")
  ```
  Leave the other three cells using the default (their visible titles already make sense to VoiceOver).

- [ ] **Step 3 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED.

- [ ] **Step 4 — Commit**

  ```bash
  git add Sources/BlueSkyTemplatesApp/HomeView.swift
  git commit -m "$(cat <<'EOF'
  fix(home): explicit "New template" a11y label on quick-action (I.B4, H3 nit)

  Visible title "New" stays (grid-fit); VoiceOver now reads "New template".

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.C1 — Phase B/D ComposeView consolidation

**Why:** Four small carry-forward nits across `ComposeView` and `TemplateEditorView` worth knocking down together.

> **NOTE:** The fifth original B-nit — `TemplateEditorView.swift:94` whitespace inconsistency between `canSave` and `save()` — was verified at plan-writing time as **already resolved** (both use `.whitespacesAndNewlines`). Dropped from this task.

**Sub-items (each a separate step set):**
1. `ComposeView.copy(_:)` adds explicit `#else` no-op for visionOS/watchOS-safety.
2. Tighten the api-nil graceful error message: "No Bluesky API client available." → "No account connected."
3. `self.send` vs bare `send` style consistency inside the submit Task closure.
4. E4 one-line comment on `.onChange(of: applier?.pending?.tick)` explaining the `consume()` re-trigger.

**Files:**
- Modify: `Sources/Compose/ComposeView.swift` (multiple locations — grep before editing)

**Behavior change:** none. Source-only.

**TDD applicability:** none.

- [ ] **Step 1 — Locate `copy(_:)` and add `#else` arm**

  ```bash
  grep -n "func copy(" Sources/Compose/ComposeView.swift
  ```

  Replace the body of `copy(_:)`:
  ```swift
  private func copy(_ string: String) {
      #if os(iOS)
      UIPasteboard.general.string = string
      #elseif os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(string, forType: .string)
      #else
      // visionOS/watchOS/etc. — no clipboard surface today. Intentional no-op;
      // revisit if a new target ships.
      _ = string
      #endif
  }
  ```

- [ ] **Step 2 — Tighten the api-nil message**

  ```bash
  grep -n "api client" Sources/Compose/ComposeView.swift
  ```

  Find the user-visible string around line 160 (per spec); replace whatever wordy "No Bluesky API client available" or similar text is there with the literal `"No account connected."` Verify the surrounding `Text(...)` still compiles.

- [ ] **Step 3 — Style consistency inside the submit Task closure**

  Around line 170 (per spec). Inside the `Task { ... }` closure that wraps `await submit()`, scan for any explicit `self.send` references vs bare `send` calls; pick the bare form (project convention — explicit `self` not required in Swift closures since SE-0269). One-line consistency fix.

  If the Task closure mixes `self.api`, `self.draft`, `send(...)`, etc., the simplest "consistent" target is: drop the leading `self.` everywhere it isn't required by the compiler to capture.

- [ ] **Step 4 — E4 comment on `.onChange(of: applier?.pending?.tick)`**

  ```bash
  grep -n "applier?.pending?.tick" Sources/Compose/ComposeView.swift
  ```

  Above the `.onChange(...)` modifier (the one with `initial: true`), add a single-line comment:
  ```swift
  // consume() below re-triggers this (pending: n → nil); guard short-circuits.
  ```

- [ ] **Step 5 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED.

- [ ] **Step 6 — Commit**

  ```bash
  git add Sources/Compose/ComposeView.swift
  git commit -m "$(cat <<'EOF'
  refactor(compose): B/D carry-forward consolidation (I.C1)

  - copy(_:) gains explicit #else no-op for non-iOS/macOS targets
  - api-nil message tightened to "No account connected."
  - submit-Task closure style normalized (drop redundant self.)
  - onChange consume()-retrigger documented inline

  Note: the TemplateEditorView whitespace nit cited in the kanban was
  already resolved before plan-write; not included.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.C2 — Phase C `ImageProcessor` cleanup

**Why:** Three nits captured in Phase C carry-forward — algorithm drift, comment style, dict-key inconsistency.

**Sub-items:**
1. Replace `stride(from: 0.85, through: 0.30, by: -0.05)` with an explicit `qualities` array — `stride(by: Double)` can drift due to float accumulation.
2. Reframe the algorithm comments at `ImageProcessor.swift:30-35` to lead with WHY (zero-count `CGImageSource` is technically valid but unusable for our pipeline) rather than restating WHAT.
3. Align CGImageDestination dict-key style — production uses `CFString` keys (line 119), test fixture uses `String` keys (`ComposeTests.swift:131`). Match production; update the fixture.

**Files:**
- Modify: `Sources/Compose/ImageProcessor.swift`
- Modify: `Tests/ComposeTests/ComposeTests.swift` (fixture only)

**Behavior change:** none. The explicit qualities array reproduces the same intended sequence; the comment reframe is text-only; the dict-key alignment is purely cosmetic (CGImageDestination accepts both via toll-free bridging).

**TDD applicability:** the existing 6 `ImageProcessor` tests guard behavior. If the qualities array change shifts output bytes, tests will fail — that's the safety net.

- [ ] **Step 1 — Read current `ImageProcessor.swift` thoroughly**

  ```bash
  cat Sources/Compose/ImageProcessor.swift
  ```

- [ ] **Step 2 — Replace `stride` with explicit array around line 62**

  Replace:
  ```swift
  for q in stride(from: 0.85, through: 0.30, by: -0.05) {
      // ...
  }
  ```
  with:
  ```swift
  // Quality ladder, descending. Explicit array so float-accumulation drift
  // in stride(by:) can't shift the boundary samples (matters at the 0.30
  // floor where one accidental 0.299999… would force another encode pass).
  let qualities: [Double] = [
      0.85, 0.80, 0.75, 0.70, 0.65,
      0.60, 0.55, 0.50, 0.45, 0.40,
      0.35, 0.30
  ]
  for q in qualities {
      // ...
  }
  ```

- [ ] **Step 3 — Reframe comments at lines 30-35**

  Open `ImageProcessor.swift:30-35`. Whatever the current comment says about iterating the CGImageSource indices, rewrite the leading line to start with the WHY:
  ```swift
  // Why this guard: CGImageSourceCreateImageAtIndex with a 0-count source
  // returns nil, but ImageIO doesn't surface a useful error — we'd just
  // get a silent encode failure downstream. Bail early so the caller sees
  // a typed error instead.
  ```

  Keep any subsequent lines that describe specific HOW details; just lead with the WHY.

- [ ] **Step 4 — Align dict-key style**

  In `Tests/ComposeTests/ComposeTests.swift:131` (the `makeFixtureJPEG` helper), find the `CGImageDestination`-options dictionary and switch its keys from `String` literals to the matching `kCGImage*` `CFString` constants — match the production style at `ImageProcessor.swift:119`. Example:
  ```swift
  // before:
  [kCGImageDestinationLossyCompressionQuality as String: 0.85]
  // after:
  [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
  ```
  (Use whatever shape the production site uses exactly.)

- [ ] **Step 5 — Verify build + tests + Xcode**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED. If any ImageProcessor test fails, the qualities-array swap shifted output bytes — narrow the array back to the exact sequence `stride` produced.

- [ ] **Step 6 — Commit**

  ```bash
  git add Sources/Compose/ImageProcessor.swift Tests/ComposeTests/ComposeTests.swift
  git commit -m "$(cat <<'EOF'
  refactor(compose): ImageProcessor cleanup (I.C2)

  - Explicit qualities ladder replaces stride(by:) (float-drift safe)
  - Algorithm comments lead with WHY (zero-count source -> bail)
  - Test fixture aligned with production CFString dict-key style

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.C3 — Phase E/F test polish

**Why:** Four small test-tidiness items from E2 / F1 / and the in-test container helper duplication.

**Sub-items:**
1. Collapse `inMemoryHashtagContainer()` into `inMemoryContainer()` in `TemplatesTests.swift:188` (duplicated factories).
2. Nest `makeFixtureJPEG` as a `static` on the `@Suite` struct in `ComposeTests.swift:107`.
3. Rename E2 suite from `"ComposeText template application"` to match the `"ComposeText validator"` cadence (e.g. `"ComposeText applyTemplate"`).
4. Rename `URLAdjacentToPunctuationReturnsTrimmedURL` (F1) to lower-camel `urlAdjacentToPunctuationReturnsTrimmedURL`.

**Files:**
- Modify: `Tests/TemplatesTests/TemplatesTests.swift`
- Modify: `Tests/ComposeTests/ComposeTests.swift`
- Modify: whatever file holds the E2 suite (search `"ComposeText template application"`)
- Modify: whatever file holds the F1 test (search `URLAdjacentToPunctuationReturnsTrimmedURL`)

**Behavior change:** none. Source-only refactor in tests.

**TDD applicability:** the changes ARE tests. Verify the suite still runs and same green count.

- [ ] **Step 1 — Locate the four sites**

  ```bash
  grep -rn "inMemoryHashtagContainer\|makeFixtureJPEG\|ComposeText template application\|URLAdjacentToPunctuationReturnsTrimmedURL" Tests/
  ```

- [ ] **Step 2 — Collapse `inMemoryHashtagContainer` into `inMemoryContainer`**

  In `TemplatesTests.swift:188`, if `inMemoryHashtagContainer()` is a thin wrapper that adds hashtags before returning, merge it into `inMemoryContainer()` by making hashtag insertion optional (a default-empty array parameter). Update all call-sites in the file.

  Skip this sub-item if the two helpers turn out to do meaningfully different things — note that in the commit message.

- [ ] **Step 3 — Nest `makeFixtureJPEG` as `static`**

  In `ComposeTests.swift:107`, move the free `makeFixtureJPEG` function inside the enclosing `@Suite struct ComposeTests` (or whatever the struct is named) as `static func makeFixtureJPEG(...) -> Data`. Update call-sites to `Self.makeFixtureJPEG(...)` or just `makeFixtureJPEG(...)` (static lookup works inside the suite struct).

- [ ] **Step 4 — Rename the E2 suite string**

  Find the `@Suite("ComposeText template application")` declaration and rename to `@Suite("ComposeText applyTemplate")` (matching the validator-cadence — verb on the method name, no extra prose). If the cadence-mate `"ComposeText validator"` uses a different shape, match it exactly.

- [ ] **Step 5 — Rename the F1 test**

  Change `@Test func URLAdjacentToPunctuationReturnsTrimmedURL()` to `@Test func urlAdjacentToPunctuationReturnsTrimmedURL()` (lower-camel — matches sibling tests).

- [ ] **Step 6 — Verify**

  ```bash
  swift test
  ```
  Expected: same green count as before this task (98/98) — pure refactor; no test was removed.

- [ ] **Step 7 — Commit**

  ```bash
  git add Tests/
  git commit -m "$(cat <<'EOF'
  test: E/F polish — helper collapse, suite renames (I.C3)

  - TemplatesTests: collapse inMemoryHashtagContainer into inMemoryContainer
  - ComposeTests: nest makeFixtureJPEG as static on the @Suite struct
  - Rename @Suite "ComposeText template application" -> applyTemplate cadence
  - Rename F1 test URLAdjacent... -> urlAdjacent... (lower-camel)

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.C4 — Phase F `ComposeView` link-state readability

**Why:** Two F5 readability nits. The inverted `if case .idle { } else { Section("Link") {…} }` reads backwards (empty then-branch); the `submit()` IIFE for assigning `card: ExternalLinkCard?` is dense.

**Files:**
- Modify: `Sources/Compose/ComposeView.swift`

**Behavior change:** none. Pure source rewrite.

**TDD applicability:** none — link-state behavior is covered by F2/F3/F4 tests; they must stay green.

- [ ] **Step 1 — Rewrite the idle/non-idle Section guard**

  ```bash
  grep -n "if case .idle" Sources/Compose/ComposeView.swift
  ```

  Find the block:
  ```swift
  if case .idle = linkState { } else {
      Section("Link") { /* preview UI */ }
  }
  ```
  and rewrite as either:
  ```swift
  switch linkState {
  case .idle:
      EmptyView()
  case .loading, .loaded, .failed:
      Section("Link") { /* preview UI */ }
  }
  ```
  OR (if the inner block only renders for `.loaded`/`.loading`/`.failed` uniformly):
  ```swift
  if !linkState.isIdle {
      Section("Link") { /* preview UI */ }
  }
  ```
  with `var isIdle: Bool { if case .idle = self { true } else { false } }` on the link-state enum.

  Pick whichever yields the cleaner diff. The switch is more explicit; the helper is shorter.

- [ ] **Step 2 — Rewrite the `submit()` IIFE**

  ```bash
  grep -n "let card: ExternalLinkCard?" Sources/Compose/ComposeView.swift
  ```

  Find:
  ```swift
  let card: ExternalLinkCard? = {
      if case .loaded(let c) = linkState { return c } else { return nil }
  }()
  ```
  Replace with direct binding:
  ```swift
  let card: ExternalLinkCard? = if case .loaded(let c) = linkState { c } else { nil }
  ```
  (Swift's `if`-expression form, Swift 5.9+.)

- [ ] **Step 3 — Verify**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED.

- [ ] **Step 4 — Commit**

  ```bash
  git add Sources/Compose/ComposeView.swift
  git commit -m "$(cat <<'EOF'
  refactor(compose): ComposeView link-state readability (I.C4)

  - if-case-idle-else inversion replaced with explicit switch
  - submit() IIFE rewritten as if-expression binding (Swift 5.9+)

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I.C5 — Phase G1 preview/type polish

**Why:** Three small G1 carry-forwards — boxing-free `id`, populated #Preview, and TemplateApplier injection on the empty-state #Preview.

**Sub-items:**
1. `TemplatePickerOption.id` returns `AnyHashable`. Replace with `var id: Self { self }` (drop the box).
2. Add `#Preview("Compose — with templates")` to `ComposeView.swift` that injects `.modelContainer(for: Template.self)` populated with 2 seed templates.
3. `TemplateListView.swift`'s empty-state `#Preview("Templates — empty")` does not inject a `TemplateApplier`. Add one for pattern consistency with the populated preview.

**Files:**
- Modify: `Sources/Compose/TemplatePickerOption.swift`
- Modify: `Sources/Compose/ComposeView.swift` (add new #Preview)
- Modify: `Sources/Templates/TemplateListView.swift:161-164` (empty-state #Preview)

**Behavior change:** none. Type internals + preview-only changes (previews don't ship to runtime).

**TDD applicability:** existing `TemplatePickerOption` tests (5 from G1.1) cover Identifiable semantics. They must stay green after the `id` change.

- [ ] **Step 1 — `TemplatePickerOption.id: Self { self }`**

  Open `Sources/Compose/TemplatePickerOption.swift`. The current declaration looks like:
  ```swift
  var id: AnyHashable { /* something */ }
  ```
  Replace with:
  ```swift
  var id: Self { self }
  ```
  This requires `TemplatePickerOption: Hashable` (it should already be — verify). Run the 5 G1.1 tests to confirm Identifiable semantics still hold.

  If `TemplatePickerOption` is `enum TemplatePickerOption: Hashable`, also confirm associated values (likely `case template(Template)`) — `Template` (the SwiftData model) is `Hashable` by `@Model` macro, so `Self` synthesis works.

- [ ] **Step 2 — Add populated #Preview to `ComposeView.swift`**

  ```bash
  grep -n "#Preview" Sources/Compose/ComposeView.swift
  ```
  Locate the existing `#Preview("Compose — idle")` and add a sibling:
  ```swift
  #Preview("Compose — with templates") {
      let config = ModelConfiguration(isStoredInMemoryOnly: true)
      let container = try! ModelContainer(for: Template.self, configurations: config)
      let context = ModelContext(container)
      context.insert(Template(title: "Daily standup", body: "What did you ship?", hashtags: ["work"]))
      context.insert(Template(title: "Hello bluesky", body: "Hi from the templates app.", hashtags: ["bsky"]))
      return ComposeView(/* same args as the idle preview */)
          .modelContainer(container)
  }
  ```
  Copy the constructor-arg list from the existing `"Compose — idle"` preview verbatim; the only delta is the `.modelContainer(container)` injection.

- [ ] **Step 3 — Inject `TemplateApplier` into empty-state preview**

  In `TemplateListView.swift:161-164`:
  ```swift
  #Preview("Templates — empty") {
      TemplateListView()
          .modelContainer(makePreviewContainer(populated: false))
  }
  ```
  becomes:
  ```swift
  #Preview("Templates — empty") {
      TemplateListView()
          .modelContainer(makePreviewContainer(populated: false))
          .environment(TemplateApplier())
  }
  ```

- [ ] **Step 4 — Verify**

  ```bash
  swift test && xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```
  Expected: 98/98, BUILD SUCCEEDED. (#Previews don't compile into the test binary, but they DO compile into the library target — a broken preview fails the build.)

- [ ] **Step 5 — Commit**

  ```bash
  git add Sources/Compose/TemplatePickerOption.swift Sources/Compose/ComposeView.swift Sources/Templates/TemplateListView.swift
  git commit -m "$(cat <<'EOF'
  refactor(g1): preview + type polish (I.C5)

  - TemplatePickerOption.id: drop AnyHashable box (id: Self { self })
  - Compose: new #Preview "with templates" with populated container
  - TemplateListView: inject TemplateApplier into empty-state #Preview

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I-review — Whole-phase reviewer subagents + kanban update

**Why:** Mirrors Phase H's `H-review`. Two subagent reviewer passes (spec-compliance + code-quality), then a kanban update capturing what's in / what's deferred.

**Files:**
- Modify: `kanban.md` (add Phase I section)

**Steps:**

- [ ] **Step 1 — Dispatch spec-compliance reviewer**

  Spawn an `Explore` subagent (or fresh `general-purpose`) with a prompt:
  > "Review the Phase I cleanup branch (`feature/phase-i-cleanup`, tip <SHA>) against `docs/specs/2026-05-21-phase-i-cleanup-design.md` and `docs/plans/2026-05-21-phase-i-cleanup.md`. Confirm every in-scope item shipped and the skip-list items did not creep in. Report any deviations."

- [ ] **Step 2 — Dispatch code-quality reviewer**

  Same shape: another subagent reviewing for naming, dead-code, missed cosmetic regressions, comment style, etc.

- [ ] **Step 3 — Address any must-fix findings**

  If either reviewer surfaces a must-fix, dispatch an additional `swift-coder` fix pass; capture nits-only findings in a new `### Deferred-cosmetic nits (Phase I)` block below.

- [ ] **Step 4 — Update `kanban.md`**

  Add a Phase I section at the top (above Phase H) following the existing template — branch, MR link (TBD until I-release), task table, deferred-nits subsection, notes. Tick all 12 task boxes.

- [ ] **Step 5 — Commit kanban update**

  ```bash
  git add kanban.md
  git commit -m "$(cat <<'EOF'
  docs(kanban): Phase I shipped — cleanup sprint

  12 tasks across plan items (#8/#10/#15), cross-cutting DS/UX nits,
  and per-phase carry-forwards. No user-visible behavior change.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## I-release — Push branch + open MR

**Steps:**

- [ ] **Step 1 — Push branch**

  ```bash
  git push -u origin feature/phase-i-cleanup
  ```

- [ ] **Step 2 — Open MR via `glab`**

  Use the `glab` skill for the exact command shape. Target branch: `main`. Title: `Phase I — Cleanup sprint`. Body links back to the spec + plan + lists the 12 task IDs.

- [ ] **Step 3 — Wait for CI pipeline green**

  ```bash
  glab ci view -b feature/phase-i-cleanup
  ```
  Expected: 98/98 JUnit, pipeline `success` on the `xcode` shell runner.

- [ ] **Step 4 — Hand off**

  Report MR URL to Dan. Dan does manual sim verification of touched surfaces (sign-out destructive tint, link card readability, home a11y) before merge.

---

## Acceptance — Phase I done when

1. All 12 in-scope task boxes ticked.
2. `swift test` 98/98 (95 baseline + 3 new in DesignSystemTests for I.A3 ×2 + I.B2 ×1).
3. `xcodebuild` against iPhone 17 sim green throughout.
4. GitLab pipeline green on the MR.
5. Both reviewer subagents ✅ APPROVED FOR MERGE.
6. `kanban.md` Phase I section captures task tally + deferred-nits subsection (if any new ones surfaced).
7. Skip-list items from the spec remain skipped (no creep).
