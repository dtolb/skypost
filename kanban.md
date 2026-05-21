# Kanban — BlueSkyTemplates v2 implementation

**Current phase:** Phase B — Compose (text-only) — stacked on `feature/templates-crud`
**Branch:** `feature/compose-text` (off `feature/templates-crud`)
**Plan:** [`docs/plans/2026-05-21-phase-b-compose-text.md`](docs/plans/2026-05-21-phase-b-compose-text.md)
**Prior phase plan (complete):** [`docs/plans/2026-05-21-phase-a-templates-crud.md`](docs/plans/2026-05-21-phase-a-templates-crud.md)

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

## Phase B — Compose (text-only)

### TODO
- **B2** — `ComposeView` with TextEditor + counter + send state (`Sources/Compose/ComposeView.swift`)
- **B3** — Wire Compose tab, extract Settings tab, delete Hello tab

### In Progress
- **B1** — `APIClient.createPost(text:)` + `ComposeText` validator + tests

### Carry-forward nits (defer to Phase D polish)
- `TemplateEditorView.swift:94` — `canSave` uses `.whitespaces`; `save()` uses `.whitespacesAndNewlines`. Pick one.
- `TemplatesTests.swift:188` — `inMemoryHashtagContainer()` duplicates `inMemoryContainer()`. Collapse.
- `TemplateEditorView.swift:134-139` — preview's `context.insert(t)` is decorative; drop or keep for symmetry.

## Upcoming phases (sketch)

- **Phase B — Compose: text only** (architecture §11 step 4)
  - ComposeView, 300-grapheme counter, send-state machine, APIClient post path
  - Template → composer hand-off
- **Phase C — Compose: images** (architecture §11 step 4 cont.)
  - PhotosPicker, per-image alt text, resize to ≤1 MB JPEG, aspect ratio
- **Phase D — Polish + tests + minor cleanups** (architecture §11 steps 5–6)
  - Pow effects with reduce-motion gates, Nuke LazyImage for previews
  - Remaining plan-file unchecked test-quality additions
  - Minor items 8, 9, 10, 12–17 from `docs/plans/2026-05-20-review-fixes.md`
- **Phase E — OAuth migration** (deferred until §7.3 trigger fires)
