# Kanban — BlueSkyTemplates v2 implementation

> **Handoff state — 2026-05-21:** Phases A → E all shipped end-to-end with full review chains. Phase E adds the missing Templates → Composer hand-off (the product link that makes the app actually USE its templates). 65/65 Swift Testing cases passing. **Simulator verification driven autonomously via cliclick + osascript (Accessibility granted)** — turned up a real bug (lazy-tab-init race on first apply) which was fixed in commit `ac60d6b` and re-verified. Full Use-Template flow now works on first apply after launch. MR !5 stacked on Phase D; bug fix already pushed.

**Current branch:** `feature/phase-e-templates-to-compose` (tip `ac60d6b`)
**Open MRs:**
- A+B: <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/2>
- C (stacked on A+B): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/3>
- D (stacked on C): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/4>
- E (stacked on D): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/5>

**Per-phase plans:**
- [Phase A — Templates CRUD](docs/plans/2026-05-21-phase-a-templates-crud.md)
- [Phase B — Compose (text)](docs/plans/2026-05-21-phase-b-compose-text.md)
- [Phase C — Compose (images)](docs/plans/2026-05-21-phase-c-compose-images.md)
- [Phase D — Polish + Pow](docs/plans/2026-05-21-phase-d-polish.md)
- [Phase E — Templates → Composer hand-off](docs/plans/2026-05-21-phase-e-templates-to-compose.md) (in flight)

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

## Phase F — sketch (post-Phase-E)

- **Phase F — OAuth migration** (deferred until §7.3 trigger fires).
- **Deferred-cleanup track**: plan #8 (App struct rename), plan #10 (@MainActor consistency), plan #12 (Keychain duplicate), plan #13 (app icon), plan #15 (DesignSystem semantic colors), ComposeView cosmetic nits (lines 75-76 ternary, `copy(_:)` missing `#else`), E2/E3/E4 cosmetic nits (this file's "Deferred-cosmetic nits (Phase E)"). Nuke LazyImage when a feed/CDN-URL surface arrives.
- **Feature track candidates**: reply / quote support, external link card embed, Save draft as template (round-trip of Phase E).
- **UI test harness**: backlog at [`docs/ui-test-backlog.md`](docs/ui-test-backlog.md); plan at [`docs/plans/2026-05-21-ui-test-harness.md`](docs/plans/2026-05-21-ui-test-harness.md). Deferred per Dan's "features for a while" directive; pick up when backlog crosses ~10 P0/P1 items or after 2-3 more feature phases.

