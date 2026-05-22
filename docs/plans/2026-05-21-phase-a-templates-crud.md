# Phase A — Templates CRUD UI

> **Source spec:** [`docs/architecture.md`](../architecture.md) §11 step 2 ("Templates port") and §6.5 (SwiftData pattern).
>
> **Goal:** Ship the Templates feature module end-to-end: list, create, edit, delete templates persisted via SwiftData. Wire it into the signed-in shell as a TabView so it's reachable from the running app.
>
> **Branch:** `feature/templates-crud` off `main` (`91e6ef6`).

## Out of scope (explicit)

- **v1 UserDefaults → SwiftData migration.** The v2 rewrite is now `main`; no
  v1 users on this device. Architecture §6.5's migration block is unneeded.
- **Compose / posting integration.** Phase B will let a Template open in the
  composer. For Phase A, templates are persisted but not yet "sendable".
- **CloudKit sync.** Architecture §11 deferred it during Phase A, so Phase A
  shipped local-only. Superseded by Phase J on 2026-05-22:
  [`2026-05-22-icloud-template-storage.md`](2026-05-22-icloud-template-storage.md).
- **Real DesignSystem styling.** The DesignSystem module stays mostly empty —
  use system semantic colors only (no literal `.red`/`.green`), no custom
  primitives yet. Minor plan item #15 stays open.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **TabView shell**, not a NavigationStack with sidebar | Architecture §6.1 anticipates "one Router per tab". Two tabs now (Templates, Hello) — Compose will replace Hello in Phase B. |
| **Templates is the first tab** (selected by default) | It's the primary feature; the hello-world tab is a sanity check that survives until Compose lands. |
| **Hashtags edited as comma-separated text**, not a token field | Smaller diff, native; `Templates.parseHashtags(_:)` normalizes (`#bsky, bsky, # bsky ` → `["bsky"]`). Token-field UI is a Phase D polish item. |
| **@Query directly in the view**, no TemplateStore wrapper | Architecture explicitly endorses this. No ViewModel layer. |
| **Tests focus on model + parsing**, not view bodies | Architecture §4: "Test `@Observable` state transitions, not view bodies." UI verified by `swift build` + manual Simulator pass. |

## Task breakdown

Tasks run sequentially (shared `.build/` race per the memory). Each dispatch
is a fresh `swift-coder` subagent with Opus 4.7 (per user instruction).

### A1 — SwiftData CRUD tests + helpers
**Owns:** `Tests/TemplatesTests/TemplatesTests.swift`, optionally
`Sources/Templates/Template.swift` (small `touch()` method only).

**TDD focus:** in-memory ModelContainer, full round-trip. Watch each test
fail first.

Tests to add:
- Insert two templates, fetch sorted by `updatedAt` desc → newest first.
- Update one template via `touch()` → it moves to the front of the sort.
- Delete one template → fetch returns the other.
- `Template` round-trips through SwiftData (id stable, hashtags preserved).
- Edge: zero templates → fetch returns `[]`.

Production additions (minimum):
- `Template.touch()` — `updatedAt = .now`. Public, `@MainActor`-safe.
- (Optional) `Template.preview` array helper for SwiftUI previews. Only add
  if the editor/list dispatch actually needs it — otherwise defer.

### A2 — TemplateListView
**Owns:** new `Sources/Templates/TemplateListView.swift`.

- `public struct TemplateListView: View`.
- `@Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]`.
- `@Environment(\.modelContext) private var modelContext`.
- Wraps in `NavigationStack` with `.navigationDestination(for: Template.self)`
  pointing at `TemplateEditorView(mode: .editing(template))`.
- Toolbar "+" presents `TemplateEditorView(mode: .new)` via a sheet (sheet, not
  push, so the user clearly distinguishes "draft new" from "open existing").
- Swipe-to-delete on each row → `modelContext.delete(template)`.
- Empty state: `ContentUnavailableView("No templates yet", systemImage:
  "doc.text", description: Text("Tap + to create one."))`.
- Row layout: title prominent, body truncated to 2 lines, hashtag chips below
  (use plain `Text` with separators for now — chip styling lands in Phase D).
- `#Preview` populates an in-memory container with `Template.previewSeeds()`
  (if helper exists) or two inline templates.

### A3 — TemplateEditorView
**Owns:** new `Sources/Templates/TemplateEditorView.swift`, plus
`parseHashtags` helper + its tests (folded into TemplatesTests).

- `public enum Mode { case new; case editing(Template) }` — exhaustive switch.
- Form: title `TextField`, body `TextEditor` (min height ~120pt), hashtags
  `TextField` showing the comma-joined parsed values, an inline footer hint
  ("Separate with commas. `#` is optional.").
- Local `@State` for typed values; on `.editing` mode, seed from the model.
- Save toolbar item: disabled when title empty; on save, either insert a new
  Template into context or mutate the existing one and call `touch()`.
- Cancel toolbar item: dismiss without writing.
- `parseHashtags(_ raw: String) -> [String]`:
  - Splits on `,`.
  - Trims whitespace.
  - Drops leading `#`.
  - Lowercases.
  - Filters empties and de-duplicates while preserving order.
- Unit-test the parser against ≥4 cases including unicode and `#  bsky`.

### A4 — TabView wiring
**Owns:** `Sources/BlueSkyTemplatesApp/RootView.swift`,
`Sources/BlueSkyTemplatesApp/HomeView.swift` (renamed),
`Sources/BlueSkyTemplatesApp/SignedInView.swift` (new).

- New `SignedInView` containing a `TabView` with:
  - Tab 1 ("Templates", `doc.text` icon): `NavigationStack { TemplateListView() }`.
  - Tab 2 ("Hello", `hand.wave` icon): the current `HomeView` body (or
    renamed `HelloTabView`).
- `RootView`'s `.signedIn(let session)` case now renders `SignedInView(session:)`.
- Keep Sign Out reachable from the Hello tab (until Settings exists).
- Confirm `.modelContainer(for: Template.self)` at App scope is sufficient —
  the Templates tab must see existing rows after relaunch.

### A5 — AuthService.convenience init cleanup (minor plan item #11)
**Owns:** `Sources/Auth/AuthService.swift`.

- Delete `convenience init()`.
- Verify build + tests still green (composition root and tests already use
  `init(provider:)`).

## Done when

1. All five tasks pass spec review + code quality review (per
   `superpowers:subagent-driven-development`).
2. `swift build` and `swift test` both green, zero warnings.
3. `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme
   BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17'`
   green.
4. Manual Simulator check (orchestrator runs): create / edit / delete a
   template, kill app, relaunch, template persists.
5. PR opened to `main` (after orchestrator coordinates with user).

## Coordination notes for subagents

- **Module-boundary rule** (from `README.md`): only `Bluesky` may import
  `ATProtoKit`. Templates must not import `Bluesky` or `Auth` for Phase A —
  it depends only on `DesignSystem` and `Models` per `Package.swift`.
- **No `print()`** anywhere. Use `Log.storage` from `AppLogging` for any
  diagnostic logging in the templates path (rare — SwiftData errors only).
- **Logging is currently not required** for CRUD — SwiftData throws
  rarely and the toolbar buttons handle failures by reverting UI state.
- **SwiftData on iOS 26**: `.modelContainer(for: Template.self)` at App
  scope auto-provisions a persistent container; `@Query` resolves it. In
  tests use `ModelContainer(for: Template.self, configurations:
  ModelConfiguration(isStoredInMemoryOnly: true))`.
- **Swift Testing** (`@Test` / `#expect`). Do NOT add XCTest.
- **`@MainActor`**: under `DefaultIsolation = MainActor`, model-context
  mutations land on main by default. Avoid sprinkling `@MainActor`
  annotations on every helper — only annotate at module boundaries when
  the compiler insists.
