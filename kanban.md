# Kanban — BlueSkyTemplates v2 implementation

> **Handoff state — 2026-05-21:** Phases A → D all shipped end-to-end with full review chains. Four MRs open against `gitlab.tolbbox.com:tolbnet/BlueSkyTemplates` (stacked). 53/53 Swift Testing cases passing. Simulator verification: login form + bad-creds error path validated (light + dark), signed-in TabView shell validated. Post-login tab content unverified manually (AppleScript taps don't land — iOS surface isn't in the macOS accessibility tree). Next session should resume from `docs/orchestrator-prompt.md`.

**Current branch:** `feature/phase-d-polish` (tip `c9ac6c2`)
**Open MRs:**
- A+B: <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/2>
- C (stacked on A+B): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/3>
- D (stacked on C): <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/4>

**Per-phase plans:**
- [Phase A — Templates CRUD](docs/plans/2026-05-21-phase-a-templates-crud.md)
- [Phase B — Compose (text)](docs/plans/2026-05-21-phase-b-compose-text.md)
- [Phase C — Compose (images)](docs/plans/2026-05-21-phase-c-compose-images.md)
- [Phase D — Polish + Pow](docs/plans/2026-05-21-phase-d-polish.md)
- **Phase E plan TBD** — orchestrator picks from `## Phase E — sketch` below

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

## Phase E — sketch

- **Phase E — OAuth migration** (deferred until §7.3 trigger fires).
- **Deferred from Phase D**: plan #8 (App struct rename), plan #10 (@MainActor consistency), plan #12 (Keychain duplicate), plan #13 (app icon), plan #15 (DesignSystem semantic colors). Nuke LazyImage when a feed/CDN-URL surface arrives.

