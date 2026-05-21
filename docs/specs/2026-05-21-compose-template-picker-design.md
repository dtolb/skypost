# Compose-first UX with in-place template picker — design

**Date:** 2026-05-21
**Status:** Approved, ready for implementation plan
**Successor of:** Phase E (Templates → Composer hand-off)
**Phase tag:** Phase G1 (first Phase G work item)

## Problem

The current app opens to the **Templates** tab. To post from a template the user must:

1. Tap a row → pushes `TemplateEditorView` (the *edit* screen)
2. Tap the `square.and.arrow.up` icon in the editor toolbar (visually reads as system Share)
3. Composer materializes with the template's body+hashtags applied

This conflates *editing a template* with *using a template to post*, and hides the primary
action (posting) behind the secondary action (editing). The Compose tab itself has no template
picker, so a user who lands there has no path to a template without backtracking.

Screenshots dated 2026-05-21 16:42–16:45 (handed in via brainstorming session) document the
pain.

## Goals

- Make **Compose** the default destination after sign-in.
- Make picking a template a first-class action **inside Compose**.
- Retire the "open Edit → tap share icon" path entirely.
- Preserve Phase E's REPLACE-on-apply semantics for the template hand-off — no new merge rules.
- Zero architecture-level changes: no new modules, no `TemplateApplier` contract changes,
  `@Query` stays in the view (architecture §6.1).

## Non-goals

- Body-preview in the picker (single-line title only).
- Sheet-style picker (deferred until template count justifies it — Menu is fine for ~tens).
- Searching/filtering templates from the picker.
- Reordering or pinning templates.
- Backwards compatibility with the share-icon path (it's being removed).

## Behavior changes

### 1. Default tab → Compose

`SignedInView.selectedTab` initial value changes from `.templates` to `.compose`. The
TabView's existing `.onChange(of: applier?.pending?.tick)` watcher continues to flip the
selection to `.compose` whenever a template is applied from elsewhere — no behavior change
on that path.

### 2. Pinned template picker row in Compose

A new `Section` added at the top of `ComposeView`'s `Form`, **above** the
"What's on your mind?" `TextField`:

```
┌─────────────────────────────┐
│  Compose                    │
├─────────────────────────────┤
│ Template:   [None ▾]        │  ← pinned row, always visible
├─────────────────────────────┤
│ What's on your mind?        │
│                             │
└─────────────────────────────┘
```

- Rendered as a `Menu` whose label is the currently-selected template title (or "None").
- Menu options: `None (blank)` + each saved template by title, sorted by `updatedAt` desc
  (same order as the Templates tab — single source of truth via `@Query`).
- Selecting a template → calls `applier.apply(template)` and lets ComposeView's existing
  `.onChange(of: applier?.pending?.tick, initial: true)` handler ingest it (REPLACE
  semantics; unchanged from Phase E).
- Selecting `None` → clears the editor locally: `text = ""`, `attachments = []`,
  `linkState = .idle`, `dismissedURLs.removeAll()`, `send = .idle`. Does **not** call
  `applier.apply` (nothing to apply) and does **not** call `applier.consume()` (no pending
  to consume). The picker's own selection state resets to `.none`.

#### Picker state

`@State private var pickerSelection: PersistentIdentifier?` (nil = None).

The picker is **transient state**, not derived from `applier.pending`. Rationale:

- After Composer ingests an applied template via `.onChange`, it calls `applier.consume()`
  which nils out `pending`. If the Menu were bound to `applier.pending`, it would snap back
  to None immediately after every apply, which doesn't match the "this is the template I'm
  using" mental model the pinned row implies.
- Tracking selection locally lets the Menu label persist until the user explicitly picks
  something else (including None).

After a successful post, the Composer's existing auto-clear path
(`.task(id: send)`) also resets `pickerSelection = nil` so a fresh draft starts blank.

### 3. Templates tab: row tap → Apply + jump

`TemplateListView` row currently uses `NavigationLink(value: template)` which pushes to
`TemplateEditorView(mode: .editing(template))`.

Replace with a plain `Button` whose action is `applier?.apply(template)`. SignedInView's
existing `.onChange(of: applier?.pending?.tick)` watcher flips `selectedTab` to
`.compose` — the user lands in Composer with the template applied. No new navigation
plumbing required.

Drop the now-redundant Use affordances:
- Remove the leading `.swipeActions(edge: .leading)` "Use" button.
- Remove the `contextMenu` "Use this template" entry (replaced by Edit/Delete; see §4).

### 4. Templates tab: Edit access via trailing swipe + context menu

With row-tap repurposed to Apply, Edit needs a new home. Use the standard iOS list pattern:

- **Trailing swipe** (Mail-style): `Edit` (blue) + `Delete` (red, destructive).
- **Context menu** (long-press): `Edit` + `Delete`.

Tapping `Edit` in either path pushes `TemplateEditorView(mode: .editing(template))` via the
existing `.navigationDestination(for: Template.self)`.

`.onDelete` is replaced by an explicit trailing-swipe Delete button so both actions live in
the same swipe drawer; behavior on actual delete is unchanged (the same
`delete(at: offsets:)` helper is invoked).

The `+` toolbar button (new template) is unchanged.

### 5. Drop the share-icon hack in Edit Template

`TemplateEditorView`'s `iOS` / `.automatic` toolbar item that calls `applier?.apply` is
removed entirely. The editor's `@Environment(TemplateApplier.self)` declaration becomes
unused and is removed too.

Toolbar after this change: `Cancel` (cancellationAction) + `Save` (primaryAction). Title
stays `"Edit Template"` / `"New Template"`. Editor stays for editing.

## Architecture impact

None. All changes are inside three existing views and the app shell:

- `Sources/BlueSkyTemplatesApp/SignedInView.swift`
- `Sources/Compose/ComposeView.swift`
- `Sources/Templates/TemplateListView.swift`
- `Sources/Templates/TemplateEditorView.swift`

Module boundaries, dependency injection, and `TemplateApplier`'s public API are unchanged.
The Compose module continues to import `Templates` (already does, for `TemplateApplier`).
ComposeView adds an `@Query(sort: \Template.updatedAt, order: .reverse)` directly — same
pattern `TemplateListView` already uses.

## Test plan (TDD)

### New tests
- **`ComposeTemplatePickerTests`** (new file under `Tests/ComposeTests/`):
  - `picker_listsTemplatesFromQuery` — given 2 templates in the model context, the
    picker's Menu enumerates them by title in `updatedAt`-desc order, with `None` first.
  - `selectingTemplate_callsApplierApply` — picking a template calls
    `applier.apply(template)` with the right value.
  - `selectingNone_clearsEditorLocalState` — sets text/attachments/link state back to
    initial; does NOT call `applier.apply` or `applier.consume`.
  - `successfulPost_resetsPickerSelectionToNone` — after `.sent` dwell + auto-clear,
    `pickerSelection == nil`.

### Updated tests
- **`TemplateListViewTests`** (or whatever the existing list test suite is named):
  - Row tap calls `applier.apply` (was: pushes to editor).
  - Trailing swipe exposes `Edit` + `Delete` actions.
  - Leading swipe is gone; "Use this template" context entry is gone.

### Removed tests
- Any assertion in `TemplateEditorView` tests that the toolbar exposes a "Use Template"
  / share-icon item.

### Manual verification (per Phase F precedent — UI lifecycle is XCUITest backlog)
- Cold launch → land on Compose tab.
- Pick a template from the picker → text fills, hashtags appear.
- Pick "None" → editor clears.
- Send post → editor + picker auto-clear after 2-second URI dwell.
- Templates tab → tap row → jump to Compose with body filled.
- Templates tab → trailing swipe → Edit pushes editor.
- Edit Template → toolbar has only Cancel + Save (no share icon).

## Migration / rollout

Single MR. No data model change. No SwiftData migration. No on-disk-format change.
Old users updating in place see: new default tab (Compose), new picker row, new list
behavior. All changes are presentational.

## Carry-forward to kanban

Add as Phase G1 under "Feature track candidates" in `kanban.md`. Update Phase G sketch to
move "Save draft as template" (the inverse round-trip) into the same conceptual cluster.

## Spec self-review

- **Placeholder scan:** None.
- **Internal consistency:** Behavior 2 (picker REPLACE) matches Behavior 3 (list-tap REPLACE)
  — both route through `applier.apply` + Composer's existing `.onChange` ingest. The picker's
  "selecting None clears editor" path is the only branch that bypasses `applier`; this is
  intentional (nothing to apply) and documented in §2.
- **Scope check:** One MR, ~4 source files, ~1 new test file, ~2 updated test files. Single
  implementation plan is appropriate.
- **Ambiguity check:** `pickerSelection`'s lifetime (transient vs. applier-derived) and the
  "selecting None" semantics were the two ambiguity hotspots — both pinned down in §2.
