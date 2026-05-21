# Kanban — BlueSkyTemplates v2 implementation

> **Handoff state — 2026-05-21:** Phases A → H shipped end-to-end. Phase H is the Mantis design-system restyle — DesignSystem module grown from a placeholder into a small primitive library (BrandColor / BrandGradient / BrandCard / BrandSectionHeader / LeadIcon / WelcomeHero / BrandTypography), a new HomeView tab driven by an in-memory SentSessionLog, and all five existing screens re-skinned with Mantis tokens while preserving every existing behavior. 95/95 Swift Testing cases on Phase H tip (4 new in `DesignSystemTests`, 3 new in `SentSessionLogTests`, 4 new in `HomeActionRoutingTests` from the new BlueSkyTemplatesAppTests target). Phase G1's `selectedTab = .compose` cold-launch default preserved. UI lifecycle still covered by the deferred XCUITest backlog. Sim verification deferred per the Phase F headless-Simulator gap.

**Current branch:** `feature/phase-h-mantis-restyle` (tip `51c5e40`)
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

## Phase H — Mantis design-system restyle ✅

**Spec:** [`docs/specs/2026-05-21-phase-h-mantis-restyle-design.md`](docs/specs/2026-05-21-phase-h-mantis-restyle-design.md)
**Plan:** [`docs/plans/2026-05-21-phase-h-mantis-restyle.md`](docs/plans/2026-05-21-phase-h-mantis-restyle.md)
**Branch:** `feature/phase-h-mantis-restyle` (tip `51c5e40`)

### Done
- ✅ **H1** — DesignSystem primitives (BrandColor, BrandGradient, BrandCard, BrandSectionHeader, LeadIcon, WelcomeHero, BrandTypography) + SentSessionLog in Compose + DesignSystemTests target + SentSessionLogTests (commit `183d1f8`; 91/91 tests, xcodebuild green)
- ✅ **H2** — LoginView WelcomeHero + BrandSectionHeader (commit `fa04230`; 91/91 tests, xcodebuild green)
- ✅ **H3** — HomeView + tab wiring + sessionLog injection (commit `8c0061f`; 95/95 tests, xcodebuild green). `AppTab` promoted to public, `.home` added at front, `selectedTab` default unchanged at `.compose`.
- ✅ **H4** — TemplateListView LeadIcon rows + WelcomeHero empty state (commit `b4a7137`; 95/95 tests, xcodebuild green)
- ✅ **H5** — TemplateEditorView BrandSectionHeader on Title/Body/Hashtags (commit `b7580c7`; 95/95 tests, xcodebuild green)
- ✅ **H6** — ComposeView `.sent(uri:)` → WelcomeHero celebration + brand-headed Images/Link + LeadIcon on picker + SentSessionLog hook in `submit()` (commit `2c76780`; 95/95 tests, xcodebuild green)
- ✅ **H7** — SettingsTabView LeadIcon rows (person.fill / key.fill / destructive sign-out) + BrandSectionHeader (commit `498225a`; 95/95 tests, xcodebuild green)
- ✅ **H8** — `.tint(BrandColor.tint)` at WindowGroup; final SignedInView tab order verified (commit `51c5e40`; 95/95 tests, xcodebuild green)
- ✅ **H-review** — spec-compliance reviewer + code-quality reviewer subagents both ✅ APPROVED FOR MERGE; 0 must-fix bugs, 13 deferred-cosmetic nits captured below

### Deferred-cosmetic nits (Phase H)

*From spec-compliance review:*
- H3 nit — `HomeView` quick-action cell label is "New" (not "New template" as spec says) — required to fit the 4-column `LazyVGrid`. Fix at `HomeView.swift:114` if the grid ever collapses to 3 columns. Cosmetic, behavior-irrelevant.
- H3 nit — Home quick-action cells use an inline `.rect(cornerRadius: 14)` rather than the 10pt-radius `BrandCard` primitive. Same visual family, different radius. `HomeView.swift:137`.
- H3 nit — "Sent this session" list rendered as a custom white rounded-rect with manual `Divider().padding(.leading, 56)` rather than the grouped `List` the spec called for. Visual consistency choice for the ScrollView layout.
- H1 nit — `WelcomeHero` API surface uses `(_:subtitle:@ViewBuilder trailing:)` rather than the spec's `(title:subtitle:trailing:)` accessory positional. Functionally equivalent; cosmetic API shape.
- H3 nit — Home hero's templates-count chip is an `.overlay(alignment: .topTrailing)` capsule rather than passed through `WelcomeHero`'s `trailing:` slot. Visually identical, structurally separate. `HomeView.swift:96-104`.
- H1 nit — `WelcomeHero.composeAccessibilityLabel("Title!", subtitle: "…")` yields `"Title!. …"` (double-period). ComposeView's `.sent` overrides with a custom label so no VoiceOver weirdness ships; primitive nit only. `WelcomeHero.swift:59`.

*From code-quality review:*
- H7 / H6 nit — `LeadIcon(...).accessibilityHidden(true)` redundancy at the call site; `LeadIcon` already calls `.accessibilityHidden(true)` internally (`LeadIcon.swift:28`). 3 occurrences in `SettingsTabView.swift:31,39,61` and 1 in `ComposeView.swift:745`. Pick one direction across the codebase: keep internal (drop call-sites) or keep call-sites (drop internal).
- H3 / H4 nit — `Color(white: 0.95)` macOS-fallback `pageBackground` duplicated in `HomeView.swift:217-223` (static var) and `TemplateListView.swift:116-122` (instance var). Also stylistically inconsistent (static vs instance). If a third site lands, promote to a `BrandColor.pageBackground` (or `BrandColor.groupedBackground`) primitive.
- H3 nit — quick-action `.accessibilityLabel(title)` reads "New" / "Compose" / "Templates" / "Settings" verbatim; "New" specifically loses context. Adding " template" suffix or a more verbose a11y label (e.g. "New template") would clarify. `HomeView.swift:140`.
- H1 nit — `BrandSectionHeader` applies `.textCase(.uppercase)` AND `.kerning(1.0)` manually, but SwiftUI's Form layer re-applies `.textCase(.uppercase)` to Section headers by default. Harmless double-uppercase on letters; the manual kerning may be re-laid out by the OS pass. Verify visually; consider `.textCase(nil)` on parent Sections (per the primitive's own docstring guidance) if kerning looks off.
- H8 carry-forward — `TemplateListView.swift:80` `.tint(.accentColor)` on the Edit swipe button. Benign — `.accentColor` resolves to the inherited `BrandColor.tint` from the WindowGroup, so the line *honors* the new app tint rather than fighting it. Could be deleted to drop the indirection, but the explicit override documents intent (non-destructive swipe button).
- H1 nit — `BrandGradient.welcome` uses pre-computed `UnitPoint` start/end values derived from 250.38°. If Mantis later tweaks the angle, two magic-number pairs would need updating in lockstep. A `private func gradientUnitPoints(forDegrees:)` helper would document the math. `BrandGradient.swift`.
- H1 nit — `LeadIcon` uses fixed 30pt frame + 15pt SF Symbol. Mantis kit also defines 22pt and 40pt variants for different row densities. Add a `LeadIcon.Size` enum when a second size is adopted; not needed yet.

### Notes
- `selectedTab` default stays `.compose` — Phase G1 cold-launch guarantee preserved.
- `TemplateApplier` hand-off still flips to `.compose` on apply (untouched in this phase).
- `SentSessionLog` is in-memory, capped at 50, cleared on process termination. No persistence; no `signOut` reset (acceptable per spec).
- 95/95 tests passing on every commit; `xcodebuild` against iPhone 17 simulator green throughout.
- Sim verification deferred to Dan (Simulator headless on this Mac per the F-sim memory).

## Phase G — sketch (post-Phase-F)

- **OAuth migration** (deferred until architecture §7.3 trigger fires).
- **Deferred-cleanup track**: plan #8 (App struct rename), plan #10 (@MainActor consistency), plan #12 (Keychain duplicate), plan #13 (app icon), plan #15 (DesignSystem semantic colors), ComposeView cosmetic nits (lines 75-76 ternary, `copy(_:)` missing `#else`), E2/E3/E4 cosmetic nits (this file's "Deferred-cosmetic nits (Phase E)"). Nuke LazyImage when a feed/CDN-URL surface arrives.
- **Feature track candidates**: reply / quote support, external link card embed, Save draft as template (round-trip of Phase E).
- **UI test harness**: backlog at [`docs/ui-test-backlog.md`](docs/ui-test-backlog.md); plan at [`docs/plans/2026-05-21-ui-test-harness.md`](docs/plans/2026-05-21-ui-test-harness.md). Deferred per Dan's "features for a while" directive; pick up when backlog crosses ~10 P0/P1 items or after 2-3 more feature phases. **Pre-pickup task:** refresh the harness plan for the post-G1 gesture surface — drop `tapUseFromContextMenu`, the "Use" swipe-button accessibilityIdentifier sweep, and the Use-Template toolbar references (plan §lines 115/119/170); add picker-Menu page-object helpers + Compose-default-tab fixture.

