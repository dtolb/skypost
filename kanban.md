# Kanban — BlueSkyTemplates v2 implementation

**Current phase:** Phase C — Compose (images) — stacked on `feature/compose-text`
**Branch:** `feature/compose-images` (off `feature/compose-text`)
**Plan:** [`docs/plans/2026-05-21-phase-c-compose-images.md`](docs/plans/2026-05-21-phase-c-compose-images.md)
**Prior phase plans (merged or pending merge):** [`docs/plans/2026-05-21-phase-a-templates-crud.md`](docs/plans/2026-05-21-phase-a-templates-crud.md), [`docs/plans/2026-05-21-phase-b-compose-text.md`](docs/plans/2026-05-21-phase-b-compose-text.md)
**Open MR for A+B combined:** <https://gitlab.tolbbox.com/tolbnet/BlueSkyTemplates/-/merge_requests/2>

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

## Phase D / E — sketch

- **Phase D — Polish + tests + minor cleanups** (architecture §11 steps 5–6) — Pow effects with reduce-motion gates, Nuke LazyImage for previews, all carry-forward nits above, retire `postHelloWorld()`, remaining plan-file unchecked items, minor items 8/10/12/13/14/15/16/17 from `docs/plans/2026-05-20-review-fixes.md`.
- **Phase E — OAuth migration** (deferred until §7.3 trigger fires).

