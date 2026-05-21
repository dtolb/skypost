# Review-fix plan — 2026-05-20

**Source review:** [`docs/reviews/2026-05-20-pre-merge-review.md`](../reviews/2026-05-20-pre-merge-review.md) (against `1571d46..8e2b434`).
**Goal:** land Critical + Important fixes, then merge `v2` → `main` via GitLab MR. Minor items are tracked here for future dispatches.

## Dispatch grouping

- **Fixer A — composition root cleanup (Critical)** → items 1, 2.
- **Fixer B — auth lifecycle + error correctness + UI submission (Important)** → items 3, 4, 5, 6, 7.
- **Fixer C — GitLab runner tag verification + push** → CI item below.
- Minor items 8–17 are recorded; defer to follow-up dispatches.

Fixers run sequentially (parallel `swift build` would race the shared `.build/` dir). All three commit on `v2`; only Fixer C pushes.

---

## Critical (Fixer A)

- [ ] **1. `BlueSkyTemplatesApp` constructs and discards an `APIClient`**
  - **Where:** `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift:21` (`@State private var api = APIClient()`) + `:26` (`let api = APIClient()` inside `init()`).
  - **Fix:** Drop the `= APIClient()` default initializer; declare `@State private var api: APIClient` and assign once in `init()` like `auth` already is. Verify the "One APIClient for the whole process" comment now matches the code.

- [ ] **2. `APIClientKey.defaultValue` eagerly constructs a hidden Keychain-touching `APIClient`**
  - **Where:** `Sources/BlueSkyTemplatesApp/EnvironmentKeys.swift:13` (`static let defaultValue: APIClient = APIClient()`).
  - **Fix:** Either change the environment value type to `APIClient?` defaulting to `nil` and force-inject everywhere it's read, **or** make the default a trapping sentinel (`{ preconditionFailure("apiClient EnvironmentValue must be injected by the App composition root") }()`). Update the one consumer (`HomeView`) accordingly. Default must not silently construct a Keychain-touching actor.

## Important (Fixer B)

- [ ] **3. Split `AuthProvider.refresh(_:)` away from the cold-launch restore path**
  - **Where:** `Sources/Auth/AuthProvider.swift:12`, `Sources/Auth/AppPasswordAuth.swift:25-30`, `Sources/Auth/AuthService.swift:67` (sentinel `SessionInfo(did: "", handle: "")`).
  - **Fix:** Replace the single `refresh(_:)` requirement with two methods: `func restore() async throws -> SessionInfo?` (no parameter, returns `nil` when no stored session — matches `APIClient.restore()`) and `func refresh(_ session: SessionInfo) async throws -> SessionInfo` (in-session rollover, called on 401; can be stubbed today). Delete the sentinel `SessionInfo` and the apology comment in `AuthService.restore()`. Update `MockAuthProvider` in `Tests/AuthTests/AuthTests.swift` accordingly and adjust the 6 transition tests.

- [ ] **4. `RootView`/`LoginView` lose user input on failure; `LoginView`'s inline error is dead code**
  - **Where:** `Sources/BlueSkyTemplatesApp/RootView.swift:16` peels off `.error` before `LoginView` sees it; inline error path is `Sources/Auth/LoginView.swift:56-62, 97-100`.
  - **Fix:** Include `.error` in the `LoginView` branch of `RootView`'s switch so the inline error row is reachable **and** the user's typed handle/password survive the failed attempt. Reserve full-screen `ErrorView` for boot/session-restore failures only. Verify `dismissError()` is wired so retry-from-error returns to `.signedOut` cleanly when needed.

- [ ] **5. Map ATProtoKit errors to user-facing reasons inside `APIClient.authenticate`**
  - **Where:** `Sources/Bluesky/APIClient.swift:67` (`throw APIError.authenticationFailed(reason: error.localizedDescription)`); surfaced via `Sources/Auth/LoginView.swift:99` + `Sources/BlueSkyTemplatesApp/RootView.swift:53`.
  - **Fix:** Add a small private mapper in `Bluesky` that translates `ATProtoError` shapes (and `URLError`s) into a closed enum of user reasons — at minimum `.badCredentials`, `.network`, `.rateLimited`, `.twoFactorRequired`, `.unknown`. Extend `APIError` with the mapped cases (or replace `authenticationFailed(reason: String)` with `authenticationFailed(reason: AuthFailureReason)`). Log the raw SDK description at `.private`; surface the mapped reason via `LocalizedError.errorDescription`.

- [ ] **6. `APIClient.restore()` swallows transient errors as if signed-out**
  - **Where:** `Sources/Bluesky/APIClient.swift:78-83`, `Sources/Auth/AuthService.swift:70-73`.
  - **Fix:** Distinguish *no token in keychain* (returns `nil` → `.signedOut`, no UI noise) from *token present but refresh failed* (network/server failure → propagate as a throw → `AuthService` lands in `.error` with retry, or keeps the cached `.signedIn(SessionInfo)` if we have one). Inspect the underlying status before deciding. A flaky network at cold launch must not silently log the user out.

- [ ] **7. `LoginView`'s `.go` submit silently no-ops when `canSubmit == false`**
  - **Where:** `Sources/Auth/LoginView.swift:41` (`.onSubmit { submit() }`).
  - **Fix:** When `submit()` short-circuits, either (a) blur focus and fire a haptic, or (b) gate the submit-button label so the keyboard shows `.return` instead of `.go` when not submittable. Pick whichever is the smaller diff and is idiomatic under iOS 26 SwiftUI keyboard APIs.

## CI (Fixer C)

- [ ] **CI. Verify the `.gitlab-ci.yml` job is tagged for the `xcode` runner; then push to `origin` (gitlab.tolbbox.com)**
  - **Where:** `.gitlab-ci.yml`.
  - **Reference:** `~/.claude/skills/gitlab-runners-tolbbox/` documents the runner tags (`macos` for Docker, `xcode` for shell). The Xcode-build job MUST be tagged `xcode`.
  - **Fix:** Read the gitlab-runners-tolbbox skill, confirm the job's `tags:` list resolves to the `xcode` shell runner (NOT `macos`), and fix if wrong. Then push `v2` to `origin` so the pipeline fires. Confirm the pipeline picks up on the right runner.

## Minor — tracked, defer to follow-up dispatches

- [ ] **8.** `BlueSkyTemplatesApp.swift` struct name shadows the containing module name. Rename the struct (`AppRoot` / `BSKApp` / `Application`) to disambiguate. Trivial.
- [ ] **9.** `EnvironmentKeys.swift` should live in `Sources/Bluesky/` (co-locate type with its environment key). Move the file once the API has stabilized.
- [ ] **10.** `@MainActor` annotation inconsistency under main-actor-by-default isolation. Either drop on `AuthService` + `AppRouter`, or document why they're kept.
- [ ] **11.** `AuthService.init()` convenience constructor smuggles a third `APIClient`. Delete the convenience init; let the composition root own wiring.
- [ ] **12.** `Sources/AppLogging/Keychain.swift:26-27` throws on `errSecDuplicateItem` from `SecItemAdd`. Address when the wrapper actually gets used (DPoP / Share Extension).
- [ ] **13.** Asset catalog ships single 1024×1024 icon — App Store will reject. Defer to spec §11 step 5 polish.
- [ ] **14.** `DesignSystem` / `Compose` / `Templates` placeholder targets pull Pow + MarkdownUI + Nuke into the build graph for 10 lines of code. Strip product deps until actually used.
- [ ] **15.** `LoginView` / `HomeView` use literal `.red` / `.green` foreground styles — should use semantic role colors. Defer to the DesignSystem dispatch.
- [ ] **16.** Force-unwrap of `URL(string: "https://bsky.app/...")!` in `LoginView`. Replace with `URL(static:)` or add an invariant comment.
- [ ] **17.** `RootView` does not reset `AuthService.state` from `.restoring` if its `.task` is cancelled mid-restore. Defensive `defer` inside `AuthService.restore()`.

## Spec-update items (for the next NEXT_STEPS revision on `main`)

- [ ] §7.2 `AuthProvider` protocol: record the split into `restore()` + `refresh(_:)` (Important #3).
- [ ] §8.4 known-gap mitigations: drop the `@unchecked @retroactive Sendable` recommendation — at ATProtoKit 0.32.5 with `@preconcurrency` + our isolation model it isn't needed.
- [ ] §9.4 keychain access group: note that the entitlement migration is deferred (matches commit `8c887a0`), not configured up front.

(These are spec-doc updates on `main`, not v2 code changes. Land them after the v2 merge.)

## Test-quality additions (folded into Fixer B where touching adjacent code)

- [ ] Edge cases in `bskyNormalizedHandle`: empty string, single `@`, `@@@`-only, unicode, whitespace-only.
- [ ] `AuthService.restore()` when provider throws an unexpected (non-`APIError.notAuthenticated`) error.
- [ ] `signOut()` from `.signingIn`.
- [ ] Assert `MockAuthProvider.revokeCalls == 1` after `signOut()`.
- [ ] `SessionInfo` round-trip via JSON.

---

## Done when

1. All Critical + Important boxes checked.
2. `swift build` / `swift test` / `xcodebuild build` all green, zero warnings.
3. `.gitlab-ci.yml` job tagged for the `xcode` runner; pipeline green on `origin`.
4. Branch pushed to `origin`; MR opened against `main` with link back to this plan and the review.
5. (User decision) Merge strategy: `git merge v2 --allow-unrelated-histories` *or* hard reset of `main` to `v2`. Confirm before pushing.
