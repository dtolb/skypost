# Phase I — Cleanup sprint (design)

**Date:** 2026-05-21
**Status:** spec → plan
**Branch (to be cut):** `feature/phase-i-cleanup` from `main` (tip `206ea8d`)
**Predecessor:** Phase H — Mantis design-system restyle (merged `206ea8d`)

## Why

Phases A → H shipped end-to-end. The kanban tail now carries:

- 5 numbered review-fix items from `docs/plans/2026-05-20-review-fixes.md` (§Minor — items 8–17), 2 of which are explicitly deferred and 1 (#15) which Phase H closed only partway.
- ~30 cross-phase carry-forward cosmetic nits.
- A handful of test-quality additions tracked since the v2 pre-merge review.

Letting this list grow longer makes each future feature phase carry more invisible drag. Phase I is one focused pass to knock down the items worth doing now, capture explicit-skip rationale for items that are not, and leave the kanban tail short before the next feature beat.

This phase changes no user-visible behavior. Test count stays at 95/95 except where noted.

## Scope

Three buckets on one branch (`feature/phase-i-cleanup`), one MR against `main`. Items are mutually independent — no MR stacking.

### I-A — Plan-numbered architectural items

| ID | Plan # | Item |
|-----|--------|------|
| I.A1 | #8 | Rename `BlueSkyTemplatesApp` struct to disambiguate from module name. Target name: `AppRoot`. |
| I.A2 | #10 | Audit `@MainActor` on `AuthService` and `AppRouter` under Swift 6 main-actor-by-default isolation; drop redundant annotations or add `// kept because …` justification. |
| I.A3 | #15 | Migrate the 5 production `.red` literals (`LoginView:132`, `ComposeView:131/159/428`, `SettingsTabView:59/63`, `RootView:56`) to the appropriate `BrandColor` semantic role. May require introducing `BrandColor.destructive` and/or `BrandColor.error` if `expenseRed` is the wrong semantic for some sites. |

### I-B — Cross-cutting DS/UX nits

| ID | Item |
|-----|------|
| I.B1 | Drop `LeadIcon(...).accessibilityHidden(true)` from 4 call-sites (`SettingsTabView` ×3, `ComposeView` ×1). `LeadIcon.swift:28` already applies it internally. Direction: keep internal, drop call-sites. |
| I.B2 | Promote duplicated `Color(white: 0.95)` macOS fallback to `BrandColor.pageBackground` primitive in DS module. Replace two consumer sites: `HomeView:217-223` and `TemplateListView:116-122`. |
| I.B3 | `TemplateListView.delete(_:)` defensively nils out `navigationTarget` when it equals the deleted template (closes narrow delete-while-edited UI race). |
| I.B4 | `HomeView` quick-action a11y label "New" → verbose "New template". |

### I-C — Per-phase carry-forward nits

Grouped by phase touched so each dispatch hits one area.

| ID | Phase | Items |
|-----|-------|-------|
| I.C1 | B/D | TemplateEditorView `canSave` and `save()` use the same whitespace character set; ComposeView `copy(_:)` adds explicit `#else` no-op (silent-drop safety for visionOS/watchOS targets if added); graceful api-nil message tightened to "No account connected."; `self.send` / `send` style consistency inside the Task closure; one-line `// consume() re-triggers; guard short-circuits` comment on E4's `.onChange(of: applier?.pending?.tick)`. |
| I.C2 | C | `ImageProcessor`: explicit qualities array (e.g. `[0.85, 0.80, ...]`) instead of `stride(from: 0.85, through: 0.30, by: -0.05)` drift; reframe algorithm comments to lead with WHY (zero-count `CGImageSource` is technically valid but unusable); CFString-keyed vs String-keyed CGImageDestination dict consistency between production and fixture. |
| I.C3 | E/F (tests) | Collapse `inMemoryHashtagContainer()` into `inMemoryContainer()`; nest `makeFixtureJPEG` as `static` on the suite struct; E2 suite name cadence (`"ComposeText template application"` → match `"ComposeText validator"` cadence); F1 `URLAdjacentToPunctuationReturnsTrimmedURL` → lower-camel `url…`. |
| I.C4 | F | ComposeView link-state readability: rewrite `if case .idle { } else { Section("Link") {…} }` (currently inverted) as `switch linkState` or guarded `if case .loaded(let card)`; rewrite `submit()`'s `let card: ExternalLinkCard? = { … }()` IIFE as direct `if case .loaded(let c)` binding. |
| I.C5 | G1 | `TemplatePickerOption.id: Self { self }` to drop the `AnyHashable` boxing; new `#Preview("Compose — with templates")` populated mirror that injects `.modelContainer(for: Template.self)` with seed data; `TemplateListView` empty-state `#Preview` injects a `TemplateApplier`. |

## Explicit skip list

These items are tracked elsewhere and intentionally not included in Phase I. Rationale captured here so future-you can re-litigate without re-discovering them.

| Item | Reason |
|------|--------|
| Plan #12 — Keychain `errSecDuplicateItem` | Deferred until DPoP / Share Extension actually uses the wrapper. Wrapper is currently unreferenced. |
| Plan #13 — App icon | Not a code task; needs actual icon-design work and asset-catalog updates. Defer to spec §11 step-5 polish phase. |
| E3 — share-icon `square.and.arrow.up` | UX decision (Share Sheet semantic conflict), not cleanup. |
| E3 — Use Template uses stored body, not `@State` edits | UX decision (auto-save? transient apply? gate?), not cleanup. |
| F4 — orphaned blob on `createRecord` failure | Bluesky GCs unreferenced blobs; no observable effect. Revisit if PDS quotas show pressure. |
| F4 — language fallback `["en"]` shape | Pathological-only (when `locale.language.languageCode` is nil); cosmetic. |
| F4 — thumbnail filename pattern | Bluesky ignores filename; cosmetic. |
| H BrandGradient angle math helper | Only matters if Mantis tweaks the angle; YAGNI. |
| H LeadIcon.Size enum | Only matters when a second size is adopted; YAGNI. |
| H WelcomeHero API shape (positional `trailing:`) | Functionally equivalent to spec; cosmetic API shape. |
| H templates-count chip as overlay vs WelcomeHero trailing slot | Visually identical, structurally separate; cosmetic. |
| H "Sent this session" custom layout vs grouped List | Visual consistency choice for the ScrollView layout. |
| H quick-action `.rect(cornerRadius: 14)` vs `BrandCard` radius | Same visual family, different radius; visual choice. |
| H BrandSectionHeader double-uppercase + kerning | Visual verification only; defer until a render issue is actually observed. |
| H8 `.tint(.accentColor)` on Edit swipe button | Documents intent (non-destructive override); benign. |
| B/D ComposeView `AnyShapeStyle` ternary symmetry (lines 75-76, 50-51) | Fights symmetry to "save" 1 line; not worth churning. |

## Out of scope

- **Test-quality additions** from `docs/plans/2026-05-20-review-fixes.md` (bskyNormalizedHandle edge cases, AuthService non-APIError throw, signOut from signingIn, MockAuthProvider revokeCalls assertion, SessionInfo JSON round-trip). These are *net-new* tests, not cleanup. If desired, open a sibling "Phase I-test" sprint.
- **Spec-doc updates** to `docs/architecture.md` (§7.2 AuthProvider split, §8.4 drop `@unchecked @retroactive Sendable` recommendation, §9.4 keychain access-group note). Doc-only; can ride the Phase I merge commit or be a separate trivial PR.

## Dispatch strategy

Sequential `swift-coder` (Opus 4.7) dispatches per the project's convention. Concurrent `swift build` races the shared `.build/` directory — sequential is non-negotiable for this repo.

Per task:

1. `swift-coder` implementer
2. spec-compliance reviewer subagent
3. code-quality reviewer subagent
4. mark task ✅ in `kanban.md`

**Order:** I-A → I-B → I-C, items as listed within each bucket. Rationale:

- I.A1 (struct rename) first — touches the `@main` symbol; doing it before other module-internal edits avoids merge conflicts in fresh dispatches.
- I.A3 (semantic colors) before I.B1 (LeadIcon a11y) — both touch `SettingsTabView` and `ComposeView`.
- I.B2 (BrandColor.pageBackground) — DS-module add; lands before any third site can sneak in.
- I-C items only touch one file area each; phase-alphabetical order.

After every commit: `swift test` + `xcodebuild` against iPhone 17 sim must stay green. Test count baseline **95/95**; only I.C3 might intentionally reduce it (suite collapses).

## Branch & MR strategy

- **Branch:** `feature/phase-i-cleanup` from `main` (tip `206ea8d`).
- **MR:** single MR at end against `main` on `gitlab.tolbbox.com`. No stacking — Phase H pattern.
- **Commits:** one logical commit per task (`I.A1`, `I.A2`, etc.). Conventional-commit prefixes consistent with existing log (`refactor:` / `feat:` / `chore:`).
- **Final reviewer:** whole-phase final reviewer at the end, mirroring Phase H's `H-review`.
- **CI:** `.gitlab-ci.yml` already wired to `xcode` runner with JUnit; pipeline must be green before merge.
- **Sim verification:** deferred per the Phase F headless-Simulator gap; Dan exercises touched surfaces (Settings sign-out tint, Compose link card, Home a11y) manually before merge.

## Risks

- **I.A2 (`@MainActor` consistency)** — Swift 6 main-actor-by-default isolation interacts with `Sendable` requirements on `AuthProvider`. Dropping `@MainActor` could surface latent isolation warnings. If it does, the task switches from "drop" to "document why kept" rather than fighting the type system. Document the decision inline.
- **I.A3 (semantic colors)** — `BrandColor.expenseRed` may not be the right semantic role for *all* 5 sites. `RootView`'s error tint and `ComposeView`'s character-overflow color likely want `BrandColor.destructive` or a new `BrandColor.error` instead. Implementer's call per site; flag the chosen names in the PR description.
- **I.B2 (`pageBackground`)** — two existing sites have different visibility scopes (one `static`, one instance). Promotion forces a naming choice; default to `BrandColor.pageBackground` (matches DS naming convention from Phase H).

## Success criteria

1. All 12 in-scope tasks ✅ in `kanban.md`.
2. `swift test` 95/95 (or matching new count if I.C3 reduces it intentionally).
3. `xcodebuild` against iPhone 17 sim green throughout.
4. GitLab pipeline green on the MR.
5. Both reviewer subagents (spec-compliance + code-quality) ✅ APPROVED FOR MERGE.
6. `kanban.md` updated with new "Phase I — Cleanup sprint" section + nits-resolved tally.
7. Skip-list items remain captured in this spec doc so future-you can re-litigate without re-discovering them.

## Done when

- Phase I branch merged into `main`.
- Carry-forward nit count in `kanban.md` reduced to: skip-list only (+ any items intentionally deferred via this spec).
- Next phase (G feature track candidates: reply/quote, save draft as template, or OAuth migration) starts from a cleaner tail.
