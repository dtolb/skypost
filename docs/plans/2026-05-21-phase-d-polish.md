# Phase D — Polish + carry-forward nits + Pow effects

> **Source spec:** [`docs/architecture.md`](../architecture.md) §11 step 5 (Pow effects with reduce-motion), §11 step 6 (test additions). Also closes carry-forward nits captured in `kanban.md` across Phases A–C, plus selected minor items from [`docs/plans/2026-05-20-review-fixes.md`](2026-05-20-review-fixes.md).
>
> **Goal:** Clean up accumulated debt + add the §11 step 5 delight effects, gated on `accessibilityReduceMotion`. No new product surfaces.
>
> **Branch:** `feature/phase-d-polish` off `feature/compose-images`.

## Out of scope (explicit)

- **Plan #8 — rename `BlueSkyTemplatesApp` struct** to avoid module-name shadow. Touches `App/Sources/AppMain.swift` (gitignored xcodeproj regen risk); defer to a stand-alone dispatch.
- **Plan #10 — `@MainActor` annotation consistency** under main-actor-by-default. Needs a design call (drop vs document); defer.
- **Plan #12 — `Sources/AppLogging/Keychain.swift` `errSecDuplicateItem` handling.** The wrapper isn't called yet (DPoP/Share Extension paths); defer until use.
- **Plan #13 — App icon catalog.** Needs design assets, not code.
- **Plan #15 — semantic role colors in LoginView (DesignSystem dispatch).** Belongs with a real DesignSystem dispatch; not Phase D.
- **Nuke LazyImage for thumbnails.** Architecture's Nuke usage is for remote URLs (Bluesky CDN). We don't have remote thumbnails in Phase D — current `AttachmentRow` uses `UIImage(data:)` on locally-encoded JPEGs, which is the right tool. Defer until a feed lands.
- **CI conversion from `xcodebuild build` to `xcodebuild test`.** Already done — see `[x] CI #2` in the 2026-05-20 review-fixes ledger. Pipeline #143 is the proof.

## Decisions taken without asking

| Decision | Rationale |
|---|---|
| **Bundle small nits into one "polish sweep" commit** instead of dispatching one per nit | Each nit is 1–3 lines. The shared `.build/` cache makes per-nit dispatches expensive; reviewers can scan a single ~50-line diff faster than chasing 10 commit links. |
| **Retire `postHelloWorld()` now**, not in a later phase | The final Phase C reviewer confirmed zero callers. Dead code in a public API is the worst kind of debt. |
| **Skip `Nuke` library entirely for Phase D** | No CDN URLs in the UI yet. Architecture §9.1 endorses Nuke *for* CDN cases. Adding it now would be cargo-cult. |
| **Pow effects: 2 effects only** (send spray + error shake) | Architecture §9.2 lists 3 (spray, shake, jump). "Jump" was for a Like button we don't have. Don't add a button just to attach an effect. |
| **`accessibilityReduceMotion` gate on every Pow modifier** | Architecture's hard rule. Wire once at the `.changeEffect`'s `isEnabled:` argument. |
| **Pow `isEnabled` reads `@Environment(\.accessibilityReduceMotion) private var reduceMotion`** in the View consuming the effect, not at the App level | SwiftUI's environment is the right place; one-shot read per View. |

## Task breakdown

Tasks run sequentially (shared `.build/` race). Each dispatched as a fresh `swift-coder` (Opus 4.7) subagent. Per the user's standing instruction, follow `superpowers:test-driven-development` + `superpowers:requesting-code-review` + `superpowers:receiving-code-review`.

### D1 — Polish sweep + `postHelloWorld()` retirement + plan #16 + plan #17
**Owns:** edits across `Sources/Templates/TemplateEditorView.swift`, `Tests/TemplatesTests/TemplatesTests.swift`, `Sources/Compose/ComposeView.swift`, `Sources/Compose/ImageProcessor.swift`, `Tests/ComposeTests/ComposeTests.swift`, `Sources/Bluesky/APIClient.swift`, `Sources/Auth/LoginView.swift`, `Sources/Auth/AuthService.swift`, `Sources/BlueSkyTemplatesApp/RootView.swift`.

Concrete edits (apply each, then run `swift build && swift test`):

1. **`TemplateEditorView.swift:94`** — change `canSave`'s `.whitespaces` to `.whitespacesAndNewlines` so it matches `save()`'s trim.
2. **`Tests/TemplatesTests/TemplatesTests.swift:188`** — delete `inMemoryHashtagContainer()`; reuse the existing `inMemoryContainer()` from the top of the file. Update the one caller in `roundTripsThroughTemplateInit`.
3. **`TemplateEditorView.swift:134-139`** — delete the `context.insert(t)` line inside `#Preview("Edit template")` — the editor binds directly to the passed-in `t`; the side-context insert was decorative.
4. **`ComposeView.swift:160`** — change the api-nil failure message from `"Composer is not connected to the network yet."` to `"No account connected."` (tighter, more accurate).
5. **`ComposeView.swift:170`** — drop the explicit `self.` prefix on `self.send = .sending` and `self.send = .sent(uri:)` inside the Task closure; match the rest of the file's local-style.
6. **`ComposeView.swift:142`** — add a one-line WHY comment to the `guard !newItems.isEmpty` short-circuit in `.onChange(of: pickerSelection)`: `// our removeAll() reset re-fires .onChange; ignore the empty round-trip.`
7. **`ComposeView.swift` `AttachmentRow`** — replace the manual `(attachment.jpegData.count / 1024) KB` formatting with `attachment.jpegData.count.formatted(.byteCount(style: .file))`. Locale-aware, no division-by-zero rounding.
8. **`ComposeView.swift` `ingest`** — at the top of the function, `attachmentError = nil` (clears any prior banner when a fresh ingest starts). Currently the banner only clears on the *next* picker open.
9. **`Sources/Bluesky/APIClient.swift`** — **delete `public func postHelloWorld() async throws -> String`** (now unreferenced post-Phase B3). Verify with `grep -rn "postHelloWorld" Sources/ Tests/ App/` before deleting.
10. **`Sources/Auth/LoginView.swift:59`** — replace `URL(string: "https://bsky.app/settings/app-passwords")!` with `URL(string: "https://bsky.app/settings/app-passwords").unsafelyUnwrapped` or — better — extract a `private static let appPasswordSettingsURL = URL(string: "https://bsky.app/settings/app-passwords")!` constant with a one-line invariant comment, and pass that to `Link(destination:)`. **Use the constant approach** so the force-unwrap is one-place, named, and documented.
11. **`Sources/BlueSkyTemplatesApp/RootView.swift`** — wrap `auth.restore()` in a `defer { auth.resetRestoringIfStuck() }` pattern. Actually simpler: add to `Sources/Auth/AuthService.swift` `restore()` a `defer { if case .restoring = state { state = .signedOut } }` so a cancelled `.task` doesn't leave the service stuck at `.restoring`. Plan #17 exactly.
12. **`Sources/Compose/ImageProcessor.swift` (Nit from C1)** — replace the floating-point `stride(from: 0.85, through: 0.30, by: -0.05)` with an explicit `let qualities: [CGFloat] = [0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30]` so the bit-pattern is deterministic.
13. **`Sources/Compose/ImageProcessor.swift` (Nit from C1 #2)** — tighten the algorithm comment block: lead with WHY (zero-count `CGImageSource` is a valid handle but unusable) rather than restating numbered WHAT steps. Keep the 5-step outline if helpful but trim restate-the-code lines.

**Tests:**
- All 52 tests must remain green.
- No new tests for the nit cleanup itself; the existing tests already cover the behavior.

### D2 — Strip placeholder dependencies from `Package.swift` (plan #14)
**Owns:** `Package.swift`.

Before: `DesignSystem` pulls Pow + MarkdownUI + Nuke; `Templates` depends on `DesignSystem` so they ride into Templates' build graph; `Compose` likewise.

After: every product dep on Pow/MarkdownUI/Nuke is REMOVED until the consumer actually imports it. Pow lands in Phase D3 (consumed inside `ComposeView` for the send spray + error shake), so Pow stays in `Compose`. MarkdownUI stays gone — no consumer. Nuke stays gone — no consumer.

Concrete edits:
- `DesignSystem` target: drop `.product(name: "Pow", package: "Pow")`, `.product(name: "MarkdownUI", package: "swift-markdown-ui")`, `.product(name: "NukeUI", package: "Nuke")`. Result: `DesignSystem` has no external dependencies. (It still depends on no first-party module — pure UI primitives layer.)
- `Compose` target: ADD `.product(name: "Pow", package: "Pow")` (needed in D3). Other Compose deps unchanged.
- Top-level `dependencies` list in Package.swift: keep all four packages still declared (ATProtoKit, Nuke, Pow, MarkdownUI) — pinning is independent of usage. The `swift-markdown-ui` and `Nuke` packages will be in the resolved graph for free; SPM only pulls source when a `.product(...)` consumer wires them in.

**Tests:** `swift build` clean and `swift test` 52 passing. No code changes outside `Package.swift`.

### D3 — Pow effects: send spray + error shake (architecture §11 step 5)
**Owns:** `Sources/Compose/ComposeView.swift` + `Sources/Auth/LoginView.swift`.

Add the two effects per architecture §9.2, with `accessibilityReduceMotion` gating in both call sites.

#### ComposeView — send spray on `.sent`

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// New @State to drive the changeEffect trigger
@State private var sendSuccessTick: Int = 0
```

In `.task(id: send)` for `.sent`, before the sleep, `sendSuccessTick += 1` so the effect fires once per success.

On the Send button (the existing `Button(action: submit) { ... }` row):

```swift
.changeEffect(
    .spray(origin: .center) {
        Image(systemName: "sparkles")
            .foregroundStyle(.tint)
    },
    value: sendSuccessTick,
    isEnabled: !reduceMotion
)
```

(`import Pow` at the top of `ComposeView.swift`. Pow is iOS-only; wrap the `import Pow` and `.changeEffect(...)` calls in `#if canImport(Pow)` — Pow targets iOS 16+; on macOS the package compiles but Pow itself is iOS-only.)

Pair with `.changeEffect(.feedback(hapticNotification: .success), value: sendSuccessTick, isEnabled: !reduceMotion)` for the haptic. (Architecture §9.2: "Always pair visual with haptic.")

#### LoginView — error shake on `.error(_, source: .signIn)`

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@State private var errorTick: Int = 0
```

In `submit()` (or via `.onChange(of: auth.state)`), when state transitions to `.error(_, .signIn)`, `errorTick += 1`. Attach to the form root or the inline error row:

```swift
.changeEffect(.shake(rate: .fast), value: errorTick, isEnabled: !reduceMotion)
.changeEffect(.feedback(hapticNotification: .error), value: errorTick, isEnabled: !reduceMotion)
```

#### Imports

Both files: `import Pow` (wrapped in `#if canImport(Pow)` so macOS builds don't break — though Pow does ship a macOS target that compiles to no-ops; verify and adjust).

**Tests:** No new tests. UI effects aren't unit-tested per architecture §4. `swift build` + `swift test` must remain clean (52 passing). `xcodebuild build -project App/BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates -destination 'platform=iOS Simulator,name=iPhone 17'` must succeed (Pow links in).

## Done when

1. All three tasks pass spec + quality review.
2. `swift build` + `swift test` green; tests count stays at 52.
3. `xcodebuild build` green on iPhone 17 Simulator.
4. Orchestrator drives a manual Simulator pass: bad-login error → screen shakes + error haptic; successful Send → sparkles spray + success haptic.
5. Carry-forward nits list in `kanban.md` is empty (Phase D drains it).
6. PR opened against `feature/compose-images` (stacked) or `main` (if MR #2/#3 are merged by then) — orchestrator coordinates.

## Coordination notes

- **Module boundary**: Pow gets added to the Compose target. Auth + Compose are the only consumers. UI files import Pow under `#if canImport(Pow)` for cross-platform safety.
- **No `print()`**.
- **Verify each D1 sub-step compiles before moving to the next** — the rolling 13-item diff is fragile to mid-step typos.
- **Test-quality additions from the 2026-05-20 review-fixes ledger** — already landed in Phases A–C (see `AuthTests.swift` and `HandleNormalizationTests.swift`). Don't re-add.
