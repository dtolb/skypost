# Phase E — Templates → Composer hand-off

> **Source spec:** [`docs/architecture.md`](../architecture.md) §6.1 (no ViewModels, env-based services), §11 step 4 trailing observation (the composer exists, but the product premise — "post templated posts" — has no actual link between the two screens). Closes the deferred-from-Phase-B carry-forward item flagged in `<deferred_work>` of [`docs/orchestrator-prompt.md`](../orchestrator-prompt.md).
>
> **Goal:** Make the product work end-to-end. From a saved template, the user taps **Use this template** → the app jumps to the Compose tab → the composer's body is pre-filled with the template body + hashtags. That's the whole loop.
>
> **Branch:** `feature/phase-e-templates-to-compose` off `feature/phase-d-polish` (Phase D's MR #4 is still stacked open; Phase E stacks on top).

## Out of scope (explicit)

- **Image attachments from the template.** Templates today carry text + hashtags only. Image-bearing templates would need a `Template.attachments` SwiftData field, a thumbnail UI in the editor, and a re-encode pass on apply. Out of scope.
- **Editing the template from the composer.** "Use this template" is one-way (template → composer). Round-tripping changes back is a separate feature (Save current draft as template) that belongs in its own phase.
- **Reply / quote / external link** features from `<deferred_work>` feature track. Independent slices; not bundled here.
- **Phase #8 (App struct rename), #10 (`@MainActor` consistency), #15 (DesignSystem semantic colors).** Defer to a follow-on cleanup phase.
- **`AppRouter` enlargement.** The current `AppRouter` is a placeholder; we don't need to grow it for Phase E. Tab selection state belongs to `SignedInView` (one consumer, no cross-tab need).
- **Programmatic tab tagging via the iOS 26 value-based `Tab { }` API.** The current implicit `.tabItem { }` style works; adding `selection:` is the minimum change. Migrate to `Tab(value:)` only when we add `Tab(role: .search)` or similar.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **Apply = REPLACE the composer text, not append.** | The composer starts empty 99 % of the time. "Use this template" is an explicit button — overwriting matters only if the user has been typing AND chose to apply a template, which is unusual. Append/prepend creates weird mash-ups (template body + half-typed sentence + hashtags). Replace is the legible behavior; the user can always re-tap a draft they care about. |
| **Hashtags concatenated onto the body** as `\n\n#tag #tag` (single space-separated line, two newlines separator). Empty body → just `#tag #tag`. Empty hashtags → just body. | Bluesky parses hashtags via facets in the body itself — there's no separate "tags" field on a post. The composer's `TextField` is one string. Two newlines mirror what the user would type by hand to set the hashtags off visually. |
| **No dedup of hashtags against tokens already in the body.** | YAGNI. Templates are user-authored — if they put `#foo` in the body AND in hashtags, that's their choice. We don't second-guess. |
| **`TemplateApplier` lives in the `Templates` module.** | Compose already depends on Templates (`Package.swift:94`). Templates is the emitter side; the contract type belongs with the emitter. No new module, no dependency cycle. |
| **`TemplateApplier` is injected via `.environment(TemplateApplier.self)` at the App composition root**, not via a typed env key. | Matches `AuthService` / `AppRouter`. Consistent with §6.1's "type-keyed environment" pattern (also flagged in §10 as the IcySky pattern to steal). |
| **Pending application carries a monotonic `tick`** so `.onChange(of: applier.pending?.tick)` re-fires when the same template is applied twice in a row. | Otherwise `.onChange` would see the same `pending` value and not fire. The tick is the standard SwiftUI "force change observation" trick. |
| **Tab selection state lives on `SignedInView`** as `@State private var selectedTab: AppTab = .templates`, not on `AppRouter`. | SignedInView is the only place that needs to read AND write it. Putting it on AppRouter would require an env round-trip with no second consumer. YAGNI. |
| **`AppTab` enum lives in `BlueSkyTemplatesApp`** module next to `SignedInView`. | One file's worth of code (3 cases). No reason to elevate it; no cross-module consumer needs it. |
| **"Use this template" affordances on TWO surfaces:** (a) `TemplateListView` row context menu, (b) `TemplateEditorView` (editing mode only) toolbar button. | The list lets the user "use" without opening; the editor lets them tweak first and then apply. New-template editor mode does NOT get the button — applying an unsaved template is semantically odd, and the user can Save → see in list → Use. |
| **No `print()` / Pow / haptic additions.** Phase D handled delight effects; Phase E is a quiet wiring task. | Keeps the review surface small. |
| **TDD on the two pure pieces** (`TemplateApplier` + `ComposeText.applyTemplate`). | View ingestion behavior is exercised end-to-end at Simulator verification; UI bodies aren't unit-tested per architecture §4. The two non-view pieces are the testable seams. |

## Task breakdown

Tasks run sequentially (shared `.build/` race). Each dispatched as a fresh `swift-coder` (Opus 4.7) subagent. Per the standing instruction, follow TDD for new behavior (E1, E2) and skip new tests for the wiring tasks (E3, E4, E5) since the existing tests already cover the underlying types. Code-quality reviewer runs after every task; spec-compliance reviewer runs in parallel with the quality reviewer on read-only commits.

### E1 — `TemplateApplier` service in `Templates` module + tests (TDD)

**Owns:**
- New file `Sources/Templates/TemplateApplier.swift`
- New test file `Tests/TemplatesTests/TemplateApplierTests.swift`

**Implementation:**

```swift
// Sources/Templates/TemplateApplier.swift
import Foundation
import Observation

/// Pending hand-off from the Templates module to whoever is listening
/// (in production: ComposeView). One-shot — the consumer calls `consume()`
/// after ingesting `pending` to clear the slot.
///
/// `tick` is monotonic across `apply(_:)` calls so `.onChange(of: pending?.tick)`
/// re-fires when the user applies the same template twice in a row.
@MainActor
@Observable
public final class TemplateApplier {

    public struct Pending: Sendable, Equatable {
        public let body: String
        public let hashtags: [String]
        public let tick: Int

        public init(body: String, hashtags: [String], tick: Int) {
            self.body = body
            self.hashtags = hashtags
            self.tick = tick
        }
    }

    public private(set) var pending: Pending?

    public init() {}

    public func apply(_ template: Template) {
        let nextTick = (pending?.tick ?? 0) + 1
        pending = Pending(
            body: template.body,
            hashtags: template.hashtags,
            tick: nextTick
        )
    }

    public func consume() {
        pending = nil
    }
}
```

**Tests (Swift Testing, `@Suite("TemplateApplier")`):**

1. `applyRecordsBodyAndHashtagsFromTemplate` — apply a `Template(title:"t", body:"hello", hashtags:["a","b"])`; expect `pending?.body == "hello"`, `pending?.hashtags == ["a", "b"]`.
2. `firstApplyStartsTickAtOne` — fresh applier, apply once; expect `pending?.tick == 1`.
3. `subsequentAppliesIncrementTickMonotonically` — apply three different templates back-to-back; expect ticks 1 → 2 → 3.
4. `consumeClearsPending` — apply then consume; expect `pending == nil`.
5. `applyAfterConsumeStartsTickAfterPriorMax` — apply, consume, apply again; expect second `pending?.tick == 2` (NOT reset to 1 — the consumer's `.onChange` cares about monotonicity, not state lineage).
6. `pendingEquatableHonorsAllFields` — two `Pending` values with same body/hashtags but different ticks are NOT equal.

**Verification gates:**
- `swift build 2>&1 | tail -8` — clean.
- `swift test 2>&1 | tail -10` — 59 passing (53 prior + 6 new).
- No `xcodebuild` for this task (no UI touched).

**Commit (heredoc, no Co-Authored-By):**
```
feat(templates): TemplateApplier service for compose hand-off
```

### E2 — `ComposeText.applyTemplate` pure merge helper + tests (TDD)

**Owns:**
- Append to `Sources/Compose/ComposeText.swift`
- Append to `Tests/ComposeTests/ComposeTests.swift`

**Implementation (added to existing `ComposeText` enum):**

```swift
/// Merge a template's body + hashtags into a single composer string.
/// Bluesky's facet parser reads hashtags from the post body itself —
/// there's no separate "tags" field — so we concatenate.
///
/// Layout:
/// - both empty → ""
/// - body only → body
/// - hashtags only → "#tag #tag"
/// - both → "body\n\n#tag #tag"
public static func applyTemplate(body: String, hashtags: [String]) -> String {
    let tags = hashtags.map { "#\($0)" }.joined(separator: " ")
    switch (body.isEmpty, tags.isEmpty) {
    case (true, true):   return ""
    case (true, false):  return tags
    case (false, true):  return body
    case (false, false): return body + "\n\n" + tags
    }
}
```

**Tests (Swift Testing, `@Suite("ComposeText template application")`):**

1. `emptyBodyAndEmptyHashtagsReturnsEmptyString`
2. `bodyOnlyReturnsBodyUnchanged` — `"hello"`, `[]` → `"hello"`.
3. `hashtagsOnlyReturnsSpaceJoinedHashTokens` — `""`, `["a","b"]` → `"#a #b"`.
4. `bodyAndHashtagsSeparatedByTwoNewlines` — `"hello"`, `["a","b"]` → `"hello\n\n#a #b"`.
5. `hashtagsArePrefixedWithHashEvenIfModelStripped` — confirms the helper adds `#` (Template stores tags without `#`).
6. `singleHashtagWorks` — `"x"`, `["only"]` → `"x\n\n#only"`.

**Verification gates:**
- `swift build` + `swift test` (65 passing: 59 + 6).

**Commit:**
```
feat(compose): ComposeText.applyTemplate body+hashtags merge helper
```

### E3 — `TemplateListView` + `TemplateEditorView` "Use this template" affordances

**Owns:**
- `Sources/Templates/TemplateListView.swift`
- `Sources/Templates/TemplateEditorView.swift`

**Concrete edits:**

1. **`TemplateListView`** — add `@Environment(TemplateApplier.self) private var applier: TemplateApplier?`. (Optional, so previews without the env value don't crash.) On the row, attach a `.contextMenu { Button { … } }` and a swipe action both labeled **"Use this template"** with `square.and.arrow.up` icon — the swipe is `.leading` so it doesn't conflict with the existing `.trailing` delete swipe. Both call `applier?.apply(template)`. The list does NOT dismiss; the tab switch happens at the App layer.
2. **`TemplateEditorView`** — add `@Environment(TemplateApplier.self) private var applier: TemplateApplier?` and `@Environment(\.dismiss) private var dismiss` (already present). In `.editing` mode only, add a leading toolbar button **"Use Template"** (`square.and.arrow.up`) to the right of Cancel; placement `.topBarLeading` on iOS. In `.new` mode this button is absent. Tapping it calls `applier?.apply(template!)` then `dismiss()`. Use a placement that doesn't collide with `.cancellationAction` — `.topBarLeading` is fine on iOS; on macOS the Form already gets a Cancel; use `.automatic` and let SwiftUI sort it.
3. **Preview safety** — both previews currently lack a `TemplateApplier` in env. Optional `@Environment` reads tolerate this, but add `.environment(TemplateApplier())` to the populated `#Preview` so the affordance is visually testable.

**Verification gates:**
- `swift build` + `swift test` (65 passing, no new tests for this task).
- `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5` → `** BUILD SUCCEEDED **`.

**Commit:**
```
feat(templates): "Use this template" affordances on row + editor
```

### E4 — `ComposeView` consumes `TemplateApplier.pending`

**Owns:**
- `Sources/Compose/ComposeView.swift`

**Concrete edits:**

1. Add `@Environment(TemplateApplier.self) private var applier: TemplateApplier?` (optional — graceful degradation in previews / tests).
2. Add a `.onChange(of: applier?.pending?.tick)` modifier on the Form (or NavigationStack root):
   ```swift
   .onChange(of: applier?.pending?.tick) { _, newTick in
       guard let newTick, let pending = applier?.pending,
             pending.tick == newTick
       else { return }
       text = ComposeText.applyTemplate(body: pending.body, hashtags: pending.hashtags)
       attachments = []                // template doesn't carry images today
       send = .idle                    // clear any prior sent-uri / error banner
       applier?.consume()
       editorFocused = true            // jump the keyboard into the now-prefilled body
   }
   ```
3. Document the WHY inline: a one-liner explaining "template application replaces text wholesale by design (see Phase E plan, decision table)."

**Verification gates:**
- `swift build` + `swift test` (65 passing).
- `xcodebuild build` succeeds.

**Commit:**
```
feat(compose): ingest TemplateApplier.pending on tick change
```

### E5 — App composition wiring + `SignedInView` tab selection + onChange reaction

**Owns:**
- `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift`
- `Sources/BlueSkyTemplatesApp/SignedInView.swift`

**Concrete edits:**

1. **`BlueSkyTemplatesApp.swift`** — add `@State private var templateApplier = TemplateApplier()` (after `auth`), and `.environment(templateApplier)` on the `RootView` chain. Import `Templates` is already present.
2. **`SignedInView.swift`** — add a private `AppTab` enum at file scope (or inside the struct as nested) with cases `.templates`, `.compose`, `.settings`. Add `@State private var selectedTab: AppTab = .templates` and `@Environment(TemplateApplier.self) private var applier: TemplateApplier?` (optional — preserves preview usability). Convert the implicit-tag `TabView { … }` to `TabView(selection: $selectedTab) { … }` and `.tag(AppTab.templates)` / `.tag(AppTab.compose)` / `.tag(AppTab.settings)` on each child. Add `.onChange(of: applier?.pending?.tick)` on the TabView:
   ```swift
   .onChange(of: applier?.pending?.tick) { _, newTick in
       if newTick != nil { selectedTab = .compose }
   }
   ```
   The composer's own `.onChange` (E4) handles consumption — SignedInView only handles tab routing.

**Verification gates:**
- `swift build` + `swift test` (65 passing).
- `xcodebuild build` succeeds.
- **Simulator pass (orchestrator drives):**
  1. Sign in.
  2. Create a template `"Daily standup"` / body `"What did you ship?"` / hashtags `bsky, work`.
  3. From the list row, swipe-leading → tap **Use this template**.
  4. Expect: app jumps to Compose tab. Body field reads `"What did you ship?\n\n#bsky #work"`. Counter shows `300 - graphemes`. Keyboard is focused.
  5. From the same list, open the template (push), tap toolbar **Use Template**; expect: sheet dismisses, tab switches, body re-filled.
  6. Apply the same template twice in a row from the editor → confirm second application still fires (tick increment).
  7. Tap **Send** with a known-good account; expect: Pow spray + success haptic (Phase D), uri appears, auto-clears at 2 s.

**Commit:**
```
feat(app): wire TemplateApplier env + Compose-tab routing
```

## Done when

1. All five tasks pass spec + quality review.
2. `swift build` + `swift test` green; tests count 65.
3. `xcodebuild build` green on iPhone 17 Simulator.
4. Orchestrator drives the manual Simulator pass above; all steps succeed.
5. Kanban rolled forward: Phase E section added with five ticked tasks; deferred-cosmetic nits list is **unchanged** (Phase E doesn't touch cosmetic debt — that's the next phase).
6. Phase E final reviewer (`swift-coder` + Opus) reviews the entire phase delta and signs off.
7. **Ask Dan before pushing** + before opening MR #5 (stacked on MR #4).

## Coordination notes

- **Module boundary** — Templates is the contract owner; Compose is the consumer; App is the wirer. No new module-level dependencies; Compose already imports Templates per Package.swift line 94.
- **No `print()`. No `MainActor.run`. No `.onAppear { Task { } }`.** The existing patterns hold.
- **`@Environment(TemplateApplier.self)` as optional** in every consumer so previews and tests don't have to inject one to compile. The App composition root is the only required injection point.
- **Tick numbering across `consume()`** — intentionally monotonic. A future consumer that cares about "first apply since launch" can compare `pending != nil` instead. The tick is for `.onChange` discrimination only.
- **Spec compliance** — architecture §6.1 ("`@Environment` for services, `@State` for UI state"), §6.2 (state-driven UI), §10 ("type-keyed environment") all reinforce this pattern. The decision to NOT touch AppRouter is consistent with §10's "Don't put state on a router just because" — implicit, but the spirit's there.
