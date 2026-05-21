# Phase G1 — Compose-first UX with in-place template picker

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task gets a fresh `swift-coder` Opus 4.7 subagent.

**Spec:** [`docs/specs/2026-05-21-compose-template-picker-design.md`](../specs/2026-05-21-compose-template-picker-design.md)

**Goal:** Make Compose the default tab, add a pinned `Template:` Menu picker to the composer, collapse the Templates-list affordances down to row-tap-applies / trailing-swipe-edit, and retire the share-icon hack in the editor toolbar.

**Architecture:** No new modules. Add one small `TemplatePickerOption` value type in the `Compose` module to give the picker testable structure; everything else is in-place edits to existing views. `TemplateApplier`'s public contract is unchanged.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Swift Testing (`@Suite` / `@Test` / `#expect`), Swift Package Manager, xcodegen → `App/BlueSkyTemplates.xcodeproj`.

**Sequencing constraint per CLAUDE memory:** "Sequential dispatches for SwiftPM repos — concurrent `swift build` races the shared `.build/`." All tasks run sequentially, never in parallel.

---

## File Structure

**Create:**
- `Sources/Compose/TemplatePickerOption.swift` — small enum + pure helper for picker entries (testable seam).
- `Tests/ComposeTests/TemplatePickerOptionTests.swift` — Swift Testing suite for the helper.

**Modify:**
- `Sources/Compose/ComposeView.swift` — add `TemplatePickerSection` at top of `Form`; add `@Query` for templates; add `pickerSelection` `@State`; wire "None" reset + template apply; reset picker on successful-post auto-clear.
- `Sources/Templates/TemplateListView.swift` — row → `Button(applier?.apply)`; drop leading `.swipeActions` "Use"; drop context-menu "Use this template"; add trailing `.swipeActions` with `Edit` + `Delete`; add context-menu `Edit` + `Delete`; replace `.onDelete` with the trailing swipe Delete button.
- `Sources/Templates/TemplateEditorView.swift` — drop the iOS / .automatic "Use Template" `ToolbarItem`s; drop the now-unused `@Environment(TemplateApplier.self)` declaration.
- `Sources/BlueSkyTemplatesApp/SignedInView.swift` — change `@State private var selectedTab: AppTab = .templates` → `= .compose`.
- `kanban.md` — append Phase G1 section under "Phase G — sketch".

**Out of scope (per spec §non-goals + Phase F precedent):**
- SwiftUI view-body unit tests (deferred to the XCUITest backlog in `docs/ui-test-backlog.md`). New testable surface area is limited to the `TemplatePickerOption` helper; all view glue is verified via `swift test` + `xcodebuild` + manual Simulator pass.

---

## Test Strategy Notes

The codebase pattern is: test pure logic helpers in Swift Testing; defer SwiftUI view-body assertions to XCUITest (currently in the deferred backlog). This plan follows that pattern — the only new unit-test surface is `TemplatePickerOption` and its helper. Existing tests for `TemplateApplier`, `ComposeText`, and `parseHashtags` continue to cover the underlying behavior the picker depends on.

Per CLAUDE memory: tests run via `swift test` on macOS; iOS Simulator builds via `xcodebuild -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" build`.

---

## Task 1: TemplatePickerOption helper — failing test

**Files:**
- Create: `Tests/ComposeTests/TemplatePickerOptionTests.swift`

- [ ] **Step 1: Write the failing test suite**

```swift
import Testing
import Foundation
import SwiftData
import Compose
import Templates

@Suite("TemplatePickerOption")
struct TemplatePickerOptionTests {

    @Test
    func optionsFromEmptyArrayReturnsJustNone() {
        let options = TemplatePickerOption.options(from: [])
        #expect(options.count == 1)
        #expect(options.first == .none)
    }

    @Test
    @MainActor
    func optionsFromTemplatesPrependsNoneAndPreservesOrder() throws {
        let container = try inMemoryTemplateContainer()
        let context = ModelContext(container)
        let first  = Template(title: "First",  body: "x", hashtags: [])
        let second = Template(title: "Second", body: "y", hashtags: [])
        context.insert(first)
        context.insert(second)
        try context.save()

        let options = TemplatePickerOption.options(from: [first, second])

        #expect(options.count == 3)
        #expect(options[0] == .none)
        #expect(options[1] == .template(first.persistentModelID, title: "First"))
        #expect(options[2] == .template(second.persistentModelID, title: "Second"))
    }

    @Test
    func noneOptionTitleIsHumanReadable() {
        #expect(TemplatePickerOption.none.menuTitle == "None (blank)")
    }

    @Test
    @MainActor
    func templateOptionTitleEchoesTemplateTitle() throws {
        let container = try inMemoryTemplateContainer()
        let context = ModelContext(container)
        let t = Template(title: "Daily Fuji", body: "x", hashtags: [])
        context.insert(t)
        try context.save()

        let option = TemplatePickerOption.template(t.persistentModelID, title: t.title)
        #expect(option.menuTitle == "Daily Fuji")
    }

    @Test
    @MainActor
    func optionsIdentifyByDistinctIDs() throws {
        let container = try inMemoryTemplateContainer()
        let context = ModelContext(container)
        let a = Template(title: "A", body: "x", hashtags: [])
        let b = Template(title: "B", body: "y", hashtags: [])
        context.insert(a)
        context.insert(b)
        try context.save()

        let options = TemplatePickerOption.options(from: [a, b])
        let ids = Set(options.map(\.id))
        #expect(ids.count == options.count, "Each option must have a unique id for ForEach")
    }
}

@MainActor
private func inMemoryTemplateContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Template.self, configurations: config)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ComposeTests.TemplatePickerOptionTests`
Expected: FAIL with "cannot find 'TemplatePickerOption' in scope".

---

## Task 2: Implement TemplatePickerOption + helper

**Files:**
- Create: `Sources/Compose/TemplatePickerOption.swift`

- [ ] **Step 1: Implement the type**

```swift
// TemplatePickerOption — value-typed picker entry for ComposeView's
// pinned template Menu.
//
// "Why a separate type?" SwiftUI's Menu / Picker / ForEach all want an
// Identifiable + Hashable choice. The picker has exactly two shapes
// (the synthetic "None" option, and one entry per saved Template), so
// an enum keeps the call sites pattern-matchable while still satisfying
// the protocols ForEach needs.
//
// The `title` is captured at option-build time rather than re-read from
// the Template at render time — keeps the option pure-value and avoids
// re-entering @MainActor from a non-isolated context.

import Foundation
import SwiftData
import Templates

public enum TemplatePickerOption: Identifiable, Hashable, Sendable {
    case none
    case template(PersistentIdentifier, title: String)

    public var id: AnyHashable {
        switch self {
        case .none:                            return AnyHashable("none")
        case .template(let pid, _):            return AnyHashable(pid)
        }
    }

    public var menuTitle: String {
        switch self {
        case .none:                            return "None (blank)"
        case .template(_, let title):          return title
        }
    }

    /// Maps a query result into a list of picker options with the
    /// synthetic "None" entry prepended. Pure — caller passes the
    /// already-sorted templates (the `@Query` in ComposeView handles
    /// the sort order; this helper is order-preserving).
    @MainActor
    public static func options(from templates: [Template]) -> [TemplatePickerOption] {
        var options: [TemplatePickerOption] = [.none]
        for t in templates {
            options.append(.template(t.persistentModelID, title: t.title))
        }
        return options
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter ComposeTests.TemplatePickerOptionTests`
Expected: PASS (5 tests).

- [ ] **Step 3: Run full Swift Testing suite to make sure nothing else broke**

Run: `swift test`
Expected: PASS (current count is 77 + 5 new = 82).

- [ ] **Step 4: Commit**

```bash
git add Sources/Compose/TemplatePickerOption.swift Tests/ComposeTests/TemplatePickerOptionTests.swift
git commit -m "$(cat <<'EOF'
feat(compose): TemplatePickerOption value type + tests

Adds a small enum + pure helper that maps [Template] -> picker entries
with a synthetic "None" prepended. Carves out the only testable seam
in the picker UX; the SwiftUI Menu wiring on top of it is plain
binding and is covered by manual Sim verify.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire the picker into ComposeView

**Files:**
- Modify: `Sources/Compose/ComposeView.swift`

- [ ] **Step 1: Add SwiftData query + picker state**

Locate the existing `@State` declarations near the top of `ComposeView` (around line 47–65). Add a SwiftData `@Query` import block and new state fields. Find this header section:

```swift
import SwiftUI
import Bluesky
import Models
import Templates
```

Add the SwiftData import:

```swift
import SwiftUI
import SwiftData
import Bluesky
import Models
import Templates
```

Then add the `@Query` + `@State` for picker selection, immediately after the existing `@Environment` declarations at the top of `ComposeView`:

```swift
@Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]

// Picker selection is TRANSIENT (not derived from applier.pending) —
// once Composer ingests an apply, applier.consume() nils pending out,
// but the picker label should keep showing "Daily Fuji" until the
// user explicitly picks something else (including "None"). nil = None.
@State private var pickerSelection: PersistentIdentifier?
```

- [ ] **Step 2: Add the picker Section at the top of the Form**

Inside `var body`, locate the first `Section` inside `Form { ... }` (currently the `TextField("What's on your mind?", ...)` section). Insert a NEW Section ABOVE it:

```swift
Form {
    Section {
        TemplatePickerLabel(
            selection: pickerSelection,
            templates: templates,
            onSelect: handlePickerSelection(_:)
        )
    } header: {
        Text("Template")
    }

    Section {
        TextField("What's on your mind?", text: $text, axis: .vertical)
            .font(.body)
            .lineLimit(8...20)
            .focused($editorFocused)
            .disabled(isSending)
    }
    // ... existing sections unchanged below ...
```

- [ ] **Step 3: Add the picker selection handler + draft reset**

In ComposeView's `// MARK: - Actions` section (near `submit()`), add:

```swift
// MARK: - Template picker

private func handlePickerSelection(_ option: TemplatePickerOption) {
    switch option {
    case .none:
        pickerSelection = nil
        resetDraft()
    case .template(let pid, _):
        pickerSelection = pid
        if let template = templates.first(where: { $0.persistentModelID == pid }) {
            applier?.apply(template)
            // applier.apply -> SignedInView's .onChange flips tab if needed,
            // and ComposeView's own .onChange(of: applier?.pending?.tick) ingests
            // the body/hashtags. Nothing else to do here.
        }
    }
}

/// Resets the editor's local state to the same shape the auto-clear
/// path uses after a successful post. Called when the user picks
/// "None" from the template picker — explicit user intent to start
/// blank.
private func resetDraft() {
    text = ""
    attachments = []
    linkState = .idle
    dismissedURLs.removeAll()
    send = .idle
}
```

- [ ] **Step 4: Reset pickerSelection in the post-send auto-clear**

Find the `.task(id: send) { ... }` block (around line 166). It currently clears `text`, `attachments`, etc. Add `pickerSelection = nil` to the reset:

```swift
.task(id: send) {
    guard case .sent = send else { return }
    sendSuccessTick += 1
    try? await Task.sleep(for: .seconds(2))
    guard case .sent = send else { return }
    text = ""
    attachments = []
    linkState = .idle
    dismissedURLs.removeAll()
    pickerSelection = nil   // ← NEW
    send = .idle
}
```

- [ ] **Step 5: Add the TemplatePickerLabel subview at the bottom of ComposeView.swift**

After the existing `private struct LinkCardRow: View { ... }` at the end of the file (around line 641), append:

```swift
// MARK: - TemplatePickerLabel

/// Pinned picker row — renders as `Template: [Title ▾]` with a Menu
/// listing "None (blank)" + every saved template. Stateless: parent
/// owns `selection`, this view just renders + forwards taps.
private struct TemplatePickerLabel: View {
    let selection: PersistentIdentifier?
    let templates: [Template]
    let onSelect: (TemplatePickerOption) -> Void

    var body: some View {
        Menu {
            ForEach(TemplatePickerOption.options(from: templates)) { option in
                Button(option.menuTitle) { onSelect(option) }
            }
        } label: {
            HStack {
                Text("Template")
                    .foregroundStyle(.primary)
                Spacer()
                Text(currentTitle)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("Template picker, currently \(currentTitle)")
    }

    private var currentTitle: String {
        guard let selection,
              let t = templates.first(where: { $0.persistentModelID == selection })
        else { return "None" }
        return t.title
    }
}
```

- [ ] **Step 6: Run Swift Testing suite**

Run: `swift test`
Expected: PASS (82 tests; no regressions).

- [ ] **Step 7: Run iOS build (compile check, no UI test)**

Run:
```bash
xcodebuild -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add Sources/Compose/ComposeView.swift
git commit -m "$(cat <<'EOF'
feat(compose): pinned template picker at top of composer

Adds a `Template: [None ▾]` Menu row above the editor. Selecting a
template routes through TemplateApplier.apply (REPLACE semantics
unchanged from Phase E); selecting None clears the draft locally.
Picker selection is transient — persists across applier.consume(),
resets on successful-post auto-clear.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Default tab → Compose

**Files:**
- Modify: `Sources/BlueSkyTemplatesApp/SignedInView.swift`

- [ ] **Step 1: Change the default**

Find `SignedInView.swift:25`:

```swift
@State private var selectedTab: AppTab = .templates
```

Change to:

```swift
@State private var selectedTab: AppTab = .compose
```

- [ ] **Step 2: Run full test suite to ensure no regressions**

Run: `swift test`
Expected: PASS (82 tests).

- [ ] **Step 3: Run iOS build**

Run:
```bash
xcodebuild -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Sources/BlueSkyTemplatesApp/SignedInView.swift
git commit -m "$(cat <<'EOF'
feat(app): default tab is Compose, not Templates

Compose is the primary destination per the new UX. The existing
.onChange(of: applier?.pending?.tick) watcher still flips tabs when
a template is applied from elsewhere — no behavior change on that
path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Templates list — row taps Apply, swipe Edits

**Files:**
- Modify: `Sources/Templates/TemplateListView.swift`

- [ ] **Step 1: Replace the `ForEach` body**

Locate the existing `ForEach(templates) { template in ... }` block (lines 31–52). Replace the entire `ForEach` (including its `.onDelete` modifier) with:

```swift
ForEach(templates) { template in
    Button {
        applier?.apply(template)
    } label: {
        TemplateRow(template: template)
    }
    .buttonStyle(.plain)
    .contextMenu {
        Button {
            navigationTarget = template
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            delete(template)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
            delete(template)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        Button {
            navigationTarget = template
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.accentColor)
    }
}
```

- [ ] **Step 2: Add `navigationTarget` @State + driven navigation**

Find the existing `@State private var newSheetPresented: Bool = false` declaration (around line 16). Add below it:

```swift
@State private var navigationTarget: Template?
```

- [ ] **Step 3: Update `.navigationDestination` and add a single-row delete helper**

Find the existing `.navigationDestination(for: Template.self) { template in ... }` block (around line 60). Replace it with a value-driven destination:

```swift
.navigationDestination(item: $navigationTarget) { template in
    TemplateEditorView(mode: .editing(template))
}
```

Add a single-row `delete(_:)` helper alongside the existing `delete(at:)` helper:

```swift
private func delete(_ template: Template) {
    modelContext.delete(template)
    try? modelContext.save()
}
```

You can keep the existing `delete(at offsets:)` helper or remove it (it's no longer referenced after `.onDelete` is gone). Remove it for cleanliness.

- [ ] **Step 4: Run full test suite**

Run: `swift test`
Expected: PASS (82 tests).

- [ ] **Step 5: Run iOS build**

Run:
```bash
xcodebuild -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Templates/TemplateListView.swift
git commit -m "$(cat <<'EOF'
refactor(templates): row tap applies template; trailing swipe edits

Row tap now calls applier.apply (was: push to editor). SignedInView's
existing tab watcher routes to Compose. The leading "Use" swipe and
context-menu "Use this template" entry are dropped — the row itself
IS the Use affordance now. Edit moved to trailing swipe + context
menu alongside Delete. Replaces .onDelete with an explicit swipe
Delete so both actions live in the same drawer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Drop the share-icon hack from Edit Template

**Files:**
- Modify: `Sources/Templates/TemplateEditorView.swift`

- [ ] **Step 1: Remove the `Use Template` ToolbarItems**

Find the `.toolbar { ... }` block in `TemplateEditorView` (lines 84–113). Remove the entire `if case .editing = mode, let template = self.template { ... }` block (lines 88–108) — that's both the iOS `.topBarTrailing` branch and the `.automatic` branch.

The resulting toolbar should only contain `Cancel` (cancellationAction) + `Save` (primaryAction):

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
    }
    ToolbarItem(placement: .primaryAction) {
        Button("Save", action: save)
            .disabled(!canSave)
    }
}
```

- [ ] **Step 2: Remove the now-unused TemplateApplier environment**

Find at line 21:

```swift
@Environment(TemplateApplier.self) private var applier: TemplateApplier?
```

Remove that line. Search the file for any other reference to `applier` — there should be none after Step 1.

- [ ] **Step 3: Update the Edit-mode preview to drop the now-unused TemplateApplier injection**

Find the `#Preview("Edit template")` block at the bottom of the file (around line 156). Remove the `.environment(TemplateApplier())` modifier:

```swift
#Preview("Edit template") {
    let container = makeEditorPreviewContainer()
    let t = Template(title: "Daily standup", body: "What did you ship?", hashtags: ["work"])
    return NavigationStack { TemplateEditorView(mode: .editing(t)) }
        .modelContainer(container)
}
```

- [ ] **Step 4: Run full test suite**

Run: `swift test`
Expected: PASS (82 tests).

- [ ] **Step 5: Run iOS build**

Run:
```bash
xcodebuild -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Templates/TemplateEditorView.swift
git commit -m "$(cat <<'EOF'
refactor(templates): drop share-icon "Use Template" toolbar item

The editor is for editing. The pinned picker in Compose + row-tap
in Templates list now own the apply path. Removes the iOS and
.automatic toolbar variants plus the now-unused TemplateApplier
environment dep.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update kanban + close out

**Files:**
- Modify: `kanban.md`

- [ ] **Step 1: Update the handoff state at the top of the file**

Replace the existing `> **Handoff state — 2026-05-21:** ...` line with:

```markdown
> **Handoff state — 2026-05-21:** Phases A → G1 shipped end-to-end. Phase G1 is the Compose-first UX refactor — Compose is now the default tab, a pinned template picker lives at the top of the composer, the Templates list row-tap applies (Edit moves to trailing swipe), and the share-icon hack in the editor toolbar is retired. 82/82 Swift Testing cases on Phase G1 tip (5 new in `TemplatePickerOptionTests`). UI lifecycle still covered by the deferred XCUITest backlog. Sim verification deferred per the Phase F headless-Simulator gap.
```

- [ ] **Step 2: Add the Phase G1 section above the existing "Phase G — sketch"**

Find the line `## Phase G — sketch (post-Phase-F)` (around line 126). Insert ABOVE it:

```markdown
## Phase G1 — Compose-first UX with in-place template picker ✅

**Spec:** [`docs/specs/2026-05-21-compose-template-picker-design.md`](docs/specs/2026-05-21-compose-template-picker-design.md)
**Plan:** [`docs/plans/2026-05-21-phase-g1-compose-template-picker.md`](docs/plans/2026-05-21-phase-g1-compose-template-picker.md)

### Done
- ✅ **G1.1** — `TemplatePickerOption` value type + 5 tests
- ✅ **G1.2** — `TemplatePickerSection` wired into ComposeView (pinned Menu row, REPLACE semantics, picker reset on auto-clear)
- ✅ **G1.3** — Default tab flipped to `.compose` in SignedInView
- ✅ **G1.4** — TemplateListView row → Apply; trailing swipe Edit+Delete; leading swipe + Use context-menu removed; `.onDelete` replaced with explicit swipe Delete
- ✅ **G1.5** — Editor "Use Template" toolbar items + TemplateApplier env dep removed

### Deferred-cosmetic nits (Phase G1)
- _(populated during phase wrap-up review)_

```

- [ ] **Step 3: Run final full test suite + iOS build sanity**

Run in sequence (NOT in parallel — per the SwiftPM `.build/` race noted in CLAUDE memory):

```bash
swift test
```
Expected: 82 tests PASS.

```bash
xcodebuild -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit the kanban update**

```bash
git add kanban.md
git commit -m "$(cat <<'EOF'
docs(kanban): Phase G1 — Compose-first UX with template picker shipped

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- §1 Default tab → Compose         → Task 4 ✓
- §2 Pinned picker in Compose      → Tasks 1, 2, 3 ✓
- §3 Templates row tap = Apply     → Task 5 ✓
- §4 Trailing swipe Edit on list   → Task 5 ✓
- §5 Drop editor share-icon hack   → Task 6 ✓
- Test plan (`TemplatePickerOption`)→ Tasks 1, 2 ✓
- Manual verification list         → noted in plan front-matter (deferred to Sim pass, per Phase F precedent)
- Kanban carry-forward             → Task 7 ✓

**Placeholder scan:** None. All code blocks are concrete.

**Type consistency:**
- `TemplatePickerOption.options(from:)` defined Task 2, consumed Task 3 ✓
- `TemplatePickerOption` cases (`.none`, `.template(PersistentIdentifier, title: String)`) consistent across tests + impl + caller ✓
- `pickerSelection: PersistentIdentifier?` — declared Task 3 Step 1, mutated Task 3 Steps 3 & 4 ✓
- `handlePickerSelection(_:)` — declared Task 3 Step 3, called from `TemplatePickerLabel`'s `onSelect` callback in Task 3 Step 2 ✓
- `navigationTarget: Template?` — declared Task 5 Step 2, mutated Task 5 Step 1, consumed Task 5 Step 3 ✓
- `delete(_:)` single-template helper — declared Task 5 Step 3, called Task 5 Step 1 ✓
- `resetDraft()` — declared Task 3 Step 3, called Task 3 Step 3 itself ✓

**Sequencing:** All tasks run sequentially via fresh `swift-coder` Opus 4.7 subagents per CLAUDE memory's SwiftPM `.build/` race constraint. No parallel dispatches.
