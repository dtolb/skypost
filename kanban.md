# Kanban — BlueSkyTemplates v2 implementation

> **Handoff state — 2026-05-21:** Phases A → G1 shipped end-to-end. Phase G1 is the Compose-first UX refactor — Compose is now the default tab, a pinned `Template: [None ▾]` Menu lives at the top of the composer, the Templates list row-tap applies (Edit moves to trailing swipe + context menu), and the share-icon hack in the editor toolbar is retired. 82/82 Swift Testing cases on Phase G1 tip (5 new in `TemplatePickerOptionTests`). UI lifecycle still covered by the deferred XCUITest backlog. Sim verification deferred per the Phase F headless-Simulator gap.

**Current branch:** `feature/phase-f-external-link-card` (tip `d1c7158`)
**Open MRs:**
- A+B: <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/2>
- C (stacked on A+B): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/3>
- D (stacked on C): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/4>
- E (stacked on D): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/5>
- F (stacked on E): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/6>

**Per-phase plans:**
- [Phase A — Templates CRUD](docs/plans/2026-05-21-phase-a-templates-crud.md)
- [Phase B — Compose (text)](docs/plans/2026-05-21-phase-b-compose-text.md)
- [Phase C — Compose (images)](docs/plans/2026-05-21-phase-c-compose-images.md)
- [Phase D — Polish + Pow](docs/plans/2026-05-21-phase-d-polish.md)
- [Phase E — Templates → Composer hand-off](docs/plans/2026-05-21-phase-e-templates-to-compose.md) (READY TO MERGE per final review)
- [Phase F — External link card embed](docs/plans/2026-05-21-phase-f-external-link-card.md) (in flight)

Orchestrator is the main session; implementers are fresh `swift-coder`
(Opus 4.7) subagents per task. Each task gets: implementer → spec-compliance
reviewer → code-quality reviewer → mark done.

## Phase A — Templates CRUD UI ✅ (READY TO MERGE per final review)

- ✅ **A1** — SwiftData CRUD tests + `Template.touch()` (commits `c3f63f9`, `251d207`; 6 tests passing)
- ✅ **A2** — TemplateListView with @Query + swipe-to-delete + stub editor (commit `01a06e7`; 29 tests passing)
- ✅ **A3** — Real TemplateEditorView + `parseHashtags` + tests (commit `ec228ca`; 35 tests passing)
- ✅ **A4** — TabView shell (commits `d335153`, `220ba41`; xcodebuild + swift test green)
- ✅ **A5** — Drop `AuthService.convenience init` (commit `007db2a`; plan item #11 closed)

**Phase A final review:** 11 files, +514 / -14, 35/35 tests green, xcodebuild green. Branch left pending push/merge for user decision.

## Phase B — Compose (text-only) ✅ (READY TO MERGE per final review)

- ✅ **B1** — `APIClient.createPost(text:)` + `ComposeText` validator + 6 tests (commit `c723e4f`; 40/40 tests passing)
- ✅ **B2** — `ComposeView` + cancellation-safe `.task(id:)` auto-clear (commit `1b75641`; xcodebuild + 40/40 tests). Side effect: closes plan #9 (env key moved to Bluesky module).
- ✅ **B3** — 3-tab shell (Templates / Compose / Settings), HelloTabView retired (commit `09c8a48`; xcodebuild + 40/40 tests)

**Phase B final review:** 6 files net change vs Phase A baseline (+ComposeView, +ComposeText, +SettingsTabView, +EnvironmentKeys-moved-to-Bluesky; -HelloTabView, -ComposeFeature.swift placeholder). Sign-in → Compose → Send call graph verified end-to-end. Branch left pending push/merge for user decision.

### Carry-forward nits (defer to Phase D polish)
- `TemplateEditorView.swift:94` — `canSave` uses `.whitespaces`; `save()` uses `.whitespacesAndNewlines`. Pick one.
- `TemplatesTests.swift:188` — `inMemoryHashtagContainer()` duplicates `inMemoryContainer()`. Collapse.
- `TemplateEditorView.swift:134-139` — preview's `context.insert(t)` is decorative; drop or keep for symmetry.
- `ComposeView.swift:50-51` — `AnyShapeStyle` on both ternary branches; symmetric but verbose.
- `ComposeView.swift:160` — graceful api-nil message could be tightened ("No account connected.").
- `ComposeView.swift:170` — explicit `self.send` vs bare `send` style inconsistency inside the Task closure.
- `APIClient.postHelloWorld()` — provably unreferenced after Phase B3 deleted HelloTabView; safe to retire.
- `ComposeView.swift` `copy(_:)` `#elseif os(macOS)` with no `#else` — silent no-op on watchOS/visionOS targets if they're ever added.

## Phase C — Compose (images)

### TODO
- _none — C3 is the last Phase C task before the wrap-up review._

### In Progress
- **C3** — `APIClient.createPost(text:images:)` + ComposeView PhotosPicker / thumbnail / alt-text wiring

### Done
- ✅ **C1** — `ImageProcessor` ImageIO resize + JPEG encode (commit `e4ff475`; 46/46 tests). Cross-platform: tests run on macOS via `swift test`.
- ✅ **C2** — `ComposeAttachment` + `isSubmittable(text:attachments:)` + 6 tests (commit `1fa71f7`; 52/52 tests passing)

### Carry-forward nits (extend Phase D list)
- `ImageProcessor.swift:62` — `stride(from: 0.85, through: 0.30, by: -0.05)` can drift; an explicit qualities array would be bit-exact.
- `ImageProcessor.swift:30-35` — algorithm comments could lead with WHY (zero-count `CGImageSource` is technically valid but unusable) instead of restating WHAT.
- `ImageProcessor.swift:119` vs `ComposeTests.swift:131` — `CFString` vs `String`-keyed CGImageDestination dict style inconsistency between production and fixture.
- `ComposeTests.swift:107` — `makeFixtureJPEG` could nest as a `static` on the suite struct for tighter scoping.

## Phase D — Polish + Pow effects ✅ (READY TO MERGE per final review)

- ✅ **D1** — polish sweep + `postHelloWorld()` retired + plans #16/#17 closed + CancellationError fix (commits `83f87b2`, `c9c24fa`; 53/53 tests passing)
- ✅ **D2** — `Package.swift` deps strip (plan #14): DesignSystem→`[]`, Pow added to Auth+Compose (commit `5a92988`; 53/53 tests passing, xcodebuild green)
- ✅ **D3** — Pow send-spray + error-shake with reduce-motion + paired haptics (commit `588b677`; 53/53 tests passing, xcodebuild green)

### Deferred-cosmetic nits (intentionally not addressed in D1)
- `ComposeView.swift:75-76` — `AnyShapeStyle` wrapper on both ternary branches. Cosmetic; revisit if it ever blocks an edit.
- `ComposeView.swift:346-353` — `copy(_:)` is `#if os(iOS)` / `#elseif os(macOS)` with no `#else`. Silent no-op on visionOS / watchOS targets if added.

## Phase E — Templates → Composer hand-off ✅ (READY TO MERGE per final review)

### In Progress
- _none — phase shipped pending Dan's manual Simulator verification._

### Done
- ✅ **E1** — `TemplateApplier` service in Templates module + 6 tests (commits `099a834` + `b18aeb1` review fixes; 59/59 tests passing)
- ✅ **E2** — `ComposeText.applyTemplate` body+hashtags merge helper + 6 tests (commit `cfd104f`; 65/65 tests passing)
- ✅ **E3** — "Use this template" UI affordances (commits `3278b09` + `6946233` review fixes; 65/65 tests passing, xcodebuild green)
- ✅ **E4** — ComposeView consumes `TemplateApplier.pending` (commit `aa2c894`; 65/65 tests passing, xcodebuild green)
- ✅ **E5** — App composition wiring + SignedInView tab routing (commit `aa31980`; 65/65 tests passing, xcodebuild green)
- ✅ **E-wrap** — final reviewer ✅ APPROVED FOR MERGE; branch pushed; MR !5 opened against `feature/phase-d-polish`
- ✅ **E-sim** — autonomous Simulator verification via cliclick + osascript (Accessibility granted): created `Daily standup` / `What did you ship?` / `bsky, work`; tested context menu, leading swipe, editor toolbar Use Template; tab routing + body fill confirmed
- ✅ **E-fix** — caught + fixed lazy-tab-init race: first Use-Template apply silently failed because TabView with `selection:` lazy-instantiates ComposeView, whose `.onChange(of: applier?.pending?.tick)` then attached with the already-bumped tick as baseline and never fired. Fix: `.onChange(of:initial:true)` (commit `ac60d6b`). Re-verified after fresh kill+relaunch.

### Deferred-cosmetic nits (Phase E)
- E2 nit — `applyTemplate` doesn't trim whitespace-only body; downstream submit gate trims so benign. One-line comment if revisited.
- E2 nit — suite name `"ComposeText template application"` doesn't match `"ComposeText validator"` cadence; cosmetic.
- E2 nit — optional `hashtagsArePassedThroughVerbatim()` test for `"two words"` → `"#two words"` to lock pass-through contract; explicitly out-of-scope per plan.
- E3 nit — `square.and.arrow.up` icon reads as Share Sheet to users; consider `text.badge.plus` / `arrow.up.doc` / `square.and.pencil` later. Bikeshed-tier.
- E3 nit — `TemplateEditorView` Use Template button uses the STORED `template.body/hashtags`, not the user's unsaved `bodyText/hashtagsRaw` `@State`. If user edits then taps Use Template, edits are ignored. Per-plan literal behavior; revisit with explicit UX call (auto-save? transient apply? gate behind `canSave`?).
- E4 nit — `ComposeView.onChange(of: applier?.pending?.tick)` re-fires once after `applier?.consume()` (pending: n → nil); guard handles it cleanly but a future reader has to derive that. One-line `// consume() below re-triggers; guard short-circuits` would document it.

## Phase F — External link card embed ✅ (READY TO MERGE per final review)

### In Progress
- _none — Sim verification deferred to Dan (Simulator headless on this Mac); MR !6 opened._

### Done
- ✅ **F1** — `URLDetector` helper via `NSDataDetector` + 6 tests (commit `0ed2949`; 71/71 tests passing)
- ✅ **F2** — `ExternalLinkCard` + `ExternalLinkResolver` protocol + `MockExternalLinkResolver` + 6 tests (commits `5aa3bcc` + `9e8f2dd` review fixes; 77/77 tests passing)
- ✅ **F3** — `LiveExternalLinkResolver` via `LPMetadataProvider` + `ImageProcessor` relocate prereq + helper tests (commits `288dd42` relocate + `c82fcbc` resolver + `cdc9ddd` review fixes; 77/77 macOS + 80/80 iOS gated, xcodebuild green)
- ✅ **F4** — `APIClient.createPost(text:external:)` overload (Option A — manual record build via `uploadBlob` + `createRecord`) + images-precedence (commits `2463591` + `b9eb0ef` review fixes; 77/77 tests passing, xcodebuild green)
- ✅ **F5** — ComposeView wiring + card preview UI (debounced `.task(id: detectedURL)`) + a11y + loading-escape (commits `8232fcf` + `e4d5749` review fixes; 77/77 tests passing, xcodebuild green)
- ✅ **F6** — App composition wiring (commit `04836d6`); whole-phase final reviewer ✅ APPROVED FOR MERGE; doc follow-ups (UI test backlog entries + carry-forward nits) at commit `d1c7158`. Sim verification blocked by headless Simulator window on this Mac — deferred to Dan's next session.

### Deferred nits (Phase F)
- F1 — characterization test for `mailto:` / `tel:` schemes. The runtime fix landed in F5 (`ComposeView.detectedURL` filters to http/https only); kanban entry remains as a *unit-test* deferral.
- F1 — test name `URLAdjacentToPunctuationReturnsTrimmedURL` uses leading-capital `URL`; siblings in the file are mixed but lower-camel preferred.
- F4 — orphaned blob on `createRecord` failure: the Option A path uploads the thumbnail blob BEFORE calling `createRecord`. If `createRecord` throws, the blob is orphaned on the user's PDS. Bluesky GCs unreferenced blobs (interval undocumented); architecture spec doesn't require cleanup. Revisit if it ever shows up in user PDS storage quotas.
- F4 — language fallback `["en"]` vs SDK's `compactMap.isEmpty ? nil : ...` form. Pathological only when `locale.language.languageCode` is nil; cosmetic.
- F4 — thumbnail filename pattern `"thumb_<uuid>.jpg"` vs SDK's `"<random>_thumbnail.jpg"`. Bluesky ignores filename; cosmetic.
- F5 — `if case .idle = linkState { } else { Section("Link") { ... } }` — empty-then-branch reads inverted vs convention; behavior correct.
- F5 — `submit()` IIFE `let card: ExternalLinkCard? = { ... }()` reads dense; `if case .loaded(let c) = linkState { card = c } else { card = nil }` would be cleaner.

## Phase G1 — Compose-first UX with in-place template picker ✅

**Spec:** [`docs/specs/2026-05-21-compose-template-picker-design.md`](docs/specs/2026-05-21-compose-template-picker-design.md)
**Plan:** [`docs/plans/2026-05-21-phase-g1-compose-template-picker.md`](docs/plans/2026-05-21-phase-g1-compose-template-picker.md)

### Done
- ✅ **G1.1** — `TemplatePickerOption` value type + 5 tests (commit `a8142c8`; 82/82 tests passing)
- ✅ **G1.2** — `TemplatePickerSection` wired into ComposeView (pinned Menu row, REPLACE semantics, picker reset on auto-clear) (commits `f433c5f` + `b0a4565` review fixes; 82/82 tests, xcodebuild green)
- ✅ **G1.3** — Default tab flipped to `.compose` in SignedInView (commit `d662ef5`; 82/82 tests, xcodebuild green)
- ✅ **G1.4** — TemplateListView row → Apply; trailing swipe Edit + Delete; leading swipe + Use context-menu removed; `.onDelete` replaced with explicit swipe Delete (commit `17d8bef`; 82/82 tests, xcodebuild green)
- ✅ **G1.5** — Editor "Use Template" toolbar items + TemplateApplier env dep removed (commit `9cd97fe`; 82/82 tests, xcodebuild green)

### Deferred-cosmetic nits (Phase G1)
- G1.1 nit — `TemplatePickerOption.id` returns `AnyHashable`; `var id: Self { self }` would drop the boxing. Cosmetic; defer.
- G1.2 nit — `#Preview("Compose — idle")` does NOT inject a populated `.modelContainer(for: Template.self)`, so the picker label always renders "None" with an empty Menu in previews. Add a `#Preview("Compose — with templates")` populated mirror when next touching the file.
- G1.4 nit — `delete(_ template:)` in `TemplateListView` does not nil out `navigationTarget` if it equals the deleted template. Narrow UI race (would require deletion while editor is pushed); one-line defensive guard recommended.
- G1.4 nit — empty-state `#Preview("Templates — empty")` does not inject `TemplateApplier`; benign because `ContentUnavailableView` has no apply path, but pattern-inconsistent with the populated preview.
- G1.5 nit — none surfaced; pure deletion change.

## Phase G — sketch (post-Phase-F)

- **OAuth migration** (deferred until architecture §7.3 trigger fires).
- **Deferred-cleanup track**: plan #8 (App struct rename), plan #10 (@MainActor consistency), plan #12 (Keychain duplicate), plan #13 (app icon), plan #15 (DesignSystem semantic colors), ComposeView cosmetic nits (lines 75-76 ternary, `copy(_:)` missing `#else`), E2/E3/E4 cosmetic nits (this file's "Deferred-cosmetic nits (Phase E)"). Nuke LazyImage when a feed/CDN-URL surface arrives.
- **Feature track candidates**: reply / quote support, external link card embed, Save draft as template (round-trip of Phase E).
- **UI test harness**: backlog at [`docs/ui-test-backlog.md`](docs/ui-test-backlog.md); plan at [`docs/plans/2026-05-21-ui-test-harness.md`](docs/plans/2026-05-21-ui-test-harness.md). Deferred per Dan's "features for a while" directive; pick up when backlog crosses ~10 P0/P1 items or after 2-3 more feature phases.

