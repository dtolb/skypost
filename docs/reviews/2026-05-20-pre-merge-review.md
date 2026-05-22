# v2 pre-merge code review — 2026-05-20

**Reviewed:** `1571d46..8e2b434` on branch `v2` (orphan)
**Spec:** [`docs/architecture.md`](../architecture.md) (originally `NEXT_STEPS_MAY_20_2026.md` on the pre-merge `main`)
**Verifications run:** `swift build` (clean, 0 warnings), `swift test` (15/15 pass), `xcodebuild build` against `iPhone 17` / iOS 26 simulator (succeeded, 1 unrelated AppIntents metadata note).

## TL;DR

**Mergeable after a small Critical fix and a couple of Important touches.** The scaffold faithfully follows the spec — modules, isolation model, `@Observable`, `os.Logger` with privacy specifiers, ATProtoKit walled off behind `Bluesky`, no banned patterns. The two real defects are (1) the composition root constructs two `APIClient` actors and throws one away, and (2) `EnvironmentKey.defaultValue` eagerly stamps a *third* `APIClient` that will perform Keychain I/O if anything ever reads it without injection. Both are easy. Beyond that the design has a few rough edges (sentinel `SessionInfo` passed to `refresh`, dead `provider` parameter, untested `LoginView` accessibility / focus assumptions), none of which block merge.

## Strengths

- **The module boundary holds.** `@preconcurrency import ATProtoKit` appears in exactly one file (`Sources/Bluesky/APIClient.swift:13`) — UI, Auth, and Models stay clean. This is the single most important architectural rule in the spec and the implementation respects it without ceremony.
- **Logging discipline is real.** Every interpolation of secret-shaped data uses an explicit privacy specifier (`Sources/Bluesky/APIClient.swift:152`: `did=\(info.did, privacy: .private(mask: .hash)) handle=\(info.handle, privacy: .public)`). No `print()` anywhere in `Sources/` or `Tests/` — the only hit is in the doc comment at `Sources/AppLogging/Log.swift:3`. The cheatsheet's ban is fully observed.
- **Idiomatic state machine for auth.** `AuthService.State` (`Sources/Auth/AuthService.swift:18-29`) covers all five transitions exhaustively. `RootView` (`Sources/BlueSkyTemplatesApp/RootView.swift:13-25`) consumes them with a `switch` — no `if let isLoggedIn` smell, no unwraps. Five state-transition tests in `Tests/AuthTests/AuthTests.swift` pin every edge.
- **Service shapes match §6.1 verbatim.** Network I/O lives in `actor APIClient` (`Sources/Bluesky/APIClient.swift:17`), state lives in `@MainActor @Observable final class AuthService` (`Sources/Auth/AuthService.swift:12-14`), DTOs (`SessionInfo`) are `Sendable, Hashable, Codable`. Approachable Concurrency is wired through the build settings (`App/project.yml:24-27`) and nothing fights it.
- **`APIError` is a clean module boundary type.** `Sources/Models/APIError.swift` flattens ATProtoKit errors to strings, conforms to `LocalizedError`, is `Sendable, Equatable`. UI gets a usable surface without importing the SDK.
- **Handle normalization is centralized at the service.** `String.bskyNormalizedHandle` (`Sources/Bluesky/APIClient.swift:163-167`) is the single source of truth — `LoginView.submit()` only trims whitespace (`Sources/Auth/LoginView.swift:107`) and forwards raw input. That's the right architectural call.
- **`swift build`, `swift test`, and `xcodebuild build` all succeed with no warnings.** That includes Swift 6 language mode + complete strict concurrency + main-actor-by-default — getting all three clean against a 0.32.x ATProtoKit transitive graph is genuinely good work.

## Critical — must fix before merge

### 1. `BlueSkyTemplatesApp` constructs and discards an `APIClient`

- **Where:** `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift:21` (`@State private var api = APIClient()`) combined with `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift:26` (`let api = APIClient()`).
- **What:** The `@State` declaration's default initializer runs first, allocating one `APIClient` actor (which writes the keychain UUID to `UserDefaults` on first launch). Then `init()` allocates a *second* `APIClient`, wraps it in `State(initialValue:)`, and assigns it through `_api`, replacing the first. The first instance is immediately orphaned. The comment two lines above promises "One APIClient for the whole process" — the code constructs two.
- **Why it matters:** Beyond the wasted allocation, this contradicts the stated invariant. If the first `APIClient` is the one accessed first under cold launch (it is — the property initializer runs at storage allocation time, before `init`), the `defaults.set(uuid.uuidString, forKey: ...)` write at `Sources/Bluesky/APIClient.swift:43` runs on instance #1; instance #2 then *reads* the value and uses the same UUID. So today's behavior is "accidentally fine." Tomorrow, if `APIClient.init` grows side effects (it almost certainly will — pipeline config, signposter, observer registration), the two-instance pattern silently does work twice and drops half of it on the floor.
- **Suggested fix:** Drop the `= APIClient()` default initializer. Declare `@State private var api: APIClient` and assign it once in `init()` like `auth` already is. The "One APIClient" comment then matches the code.

### 2. `APIClientKey.defaultValue` will eagerly construct a hidden Keychain-touching `APIClient` if read

- **Where:** `Sources/BlueSkyTemplatesApp/EnvironmentKeys.swift:13` (`static let defaultValue: APIClient = APIClient()`).
- **What:** `EnvironmentKey.defaultValue` is the value SwiftUI hands you when no `.environment(\.apiClient, ...)` is in scope. The expression `APIClient()` performs `UserDefaults` reads/writes and instantiates an `AppleSecureKeychain` actor. Today the app always injects (in `BlueSkyTemplatesApp.body`), so the default is never read at runtime. But:
  - In SwiftUI Previews, `@Environment(\.apiClient)` resolves to the default — a real, Keychain-backed client.
  - Any test or `XCUIApplication` snapshot that mounts `HomeView` without injecting will quietly hit the same path.
  - A future refactor that adds a tab containing `HomeView` without re-injecting the environment will silently bind to a parallel `APIClient` with the same UUID but a divergent in-memory session — exactly the kind of "three independent in-memory auth states" bug §2 calls out from v1.
- **Why it matters:** This is the same shape of foot-gun the v1 audit identified, just hidden inside an environment default. It also means *any* preview of `HomeView` performs Keychain I/O.
- **Suggested fix:** Make the default a fatal-on-access sentinel: a `nonisolated(unsafe) static let defaultValue: APIClient = { preconditionFailure("apiClient EnvironmentValue must be injected by the App composition root") }()` pattern, or change the environment value type to `APIClient?` defaulting to `nil` and force-inject. Either way, the default must not silently construct a Keychain-touching actor.

## Important — should fix before merge, won't block

### 3. `AuthProvider.refresh(_:)` parameter is dead; `AuthService.restore()` fakes a sentinel `SessionInfo`

- **Where:** `Sources/Auth/AuthProvider.swift:12` (`func refresh(_ session: SessionInfo) async throws -> SessionInfo`), `Sources/Auth/AppPasswordAuth.swift:25-30` (parameter unused), `Sources/Auth/AuthService.swift:67` (`let placeholder = SessionInfo(did: "", handle: "")`).
- **What:** The protocol demands a `SessionInfo` to refresh against. `AppPasswordAuth` ignores it — the real session handle is in the Keychain. `AuthService.restore()` papers over the mismatch by constructing `SessionInfo(did: "", handle: "")` purely to satisfy the signature; the only behavior keyed off the parameter is the comment at `Sources/Auth/AuthService.swift:64-66` apologizing for it. This is the exact "leaky" parameter the prior dispatch report flagged for the spec's draft protocol.
- **Why it matters:** A future `OAuthAuth` impl *will* need session state to refresh (DPoP key + access token + refresh token are session-bound), so the parameter isn't wrong in principle — but the way it's shaped now, the call sites lie about owning a session. It also means the "what does `refresh` mean at cold launch" question has no honest answer. The current shape will rot the moment OAuth lands.
- **Suggested fix:** Split the protocol along the actual lifecycle: `func restore() async throws -> SessionInfo?` (no parameter, returns `nil` if no stored session — matches `APIClient.restore()`'s existing shape) and `func refresh(_ session: SessionInfo) async throws -> SessionInfo` (in-session token rollover, called by the API path on 401). Today only `restore()` is wired; `refresh()` can be deferred or stubbed. The sentinel `SessionInfo` and the apology comment both go away.

### 4. `RootView` blocks `LoginView` behind `.signingIn` instead of showing it busy

- **Where:** `Sources/BlueSkyTemplatesApp/RootView.swift:16` (`case .signedOut, .signingIn: LoginView()`).
- **What:** During `.signingIn` the view *is* `LoginView`, and `LoginView.isBusy` checks `auth.state` (`Sources/Auth/LoginView.swift:86-89`) to disable inputs and show the spinner. Good. But there's a subtle bug: when sign-in succeeds, `RootView` transitions to `HomeView`, which forces SwiftUI to tear down `LoginView` — including the `$handle` / `$appPassword` `@State`. On a failure, transition is `.signingIn -> .error`, and `RootView` swaps in the centered full-screen `ErrorView`. The user's typed handle and password are now gone, and "Try again" only returns to `.signedOut` — i.e. the empty `LoginView`. So a fat-finger on the password forces re-typing the handle too.
- **Why it matters:** Lousy UX for a personal app where the user re-auths every 2 weeks (per §7's app-password ceiling). Also, `LoginView`'s inline error row (`Sources/Auth/LoginView.swift:56-62`) is never reachable — `RootView` peels off `.error` before `LoginView` ever sees it. So the inline error UI is dead code.
- **Suggested fix:** Either (a) include `.error` in the `LoginView` branch so its inline error row is reachable and inputs survive, then reserve `ErrorView` for boot-time / session-restore failures only, or (b) delete the inline error code from `LoginView` (`Sources/Auth/LoginView.swift:56-62, 97-100`) and acknowledge that errors always go full-screen.

### 5. `APIError.authenticationFailed(reason:)` propagates ATProtoKit's raw error string to the UI

- **Where:** `Sources/Bluesky/APIClient.swift:67` (`throw APIError.authenticationFailed(reason: error.localizedDescription)`), surfaced to the user via `Sources/Auth/LoginView.swift:99` and `Sources/BlueSkyTemplatesApp/RootView.swift:53`.
- **What:** On sign-in failure, ATProtoKit's `localizedDescription` is rendered verbatim ("Sign-in failed: \(reason)"). I checked `ATProtoError.swift` — current shapes are server-message style ("AuthenticationRequired", "InvalidRequest: …"), so no token/password leakage today. But the *abstraction is fragile*: a future ATProtoKit version could include request bodies in error descriptions (it already prints them in places per spec §8.4), and we'd ship that to the UI without re-screening.
- **Why it matters:** This is the same class of bug as v1's `print(payload)` — accidentally surfacing wire-level data through a thin error wrapper. Even today the messages are bad UX: "Sign-in failed: AuthenticationRequired" tells a user nothing.
- **Suggested fix:** Map ATProtoKit errors to a small enum of user-facing reasons (`.badCredentials`, `.network`, `.rateLimited`, `.twoFactorRequired`, `.unknown`) inside `APIClient.authenticate`. Log the raw description with `.private`; show the mapped message in UI.

### 6. `restore()` swallows non-"missing session" errors as if they were missing-session

- **Where:** `Sources/Bluesky/APIClient.swift:78-83`, `Sources/Auth/AuthService.swift:70-73`.
- **What:** Any error from `cfg.refreshSession()` — network timeout, server 500, malformed Keychain data, etc. — returns `nil` from `APIClient.restore()` and lands `AuthService` in `.signedOut`. The user is then shown a login form for a problem that has nothing to do with credentials.
- **Why it matters:** The user-facing model becomes "I was signed in, I opened the app, now I have to sign in again" — even though their refresh token is still valid and the next request would have worked. Worst case: a flaky network at cold launch silently logs the user out.
- **Suggested fix:** Distinguish *no token in keychain* (truly signed out, no UI noise) from *token present but refresh failed* (transient — leave state at `.signedIn(cachedSession)` or transition to `.error` with retry, don't silently drop to `.signedOut`). Inspect the underlying `OSStatus` from the keychain probe before deciding.

### 7. `LoginView` mishandles the keyboard's `.go` submit when `canSubmit` is false

- **Where:** `Sources/Auth/LoginView.swift:41` (`.onSubmit { submit() }`).
- **What:** `submit()` early-returns if `!canSubmit`, but the keyboard's return key doesn't lose focus. With both fields empty the user taps `.go`, nothing visibly happens. No haptic, no shake, no indication.
- **Why it matters:** Minor UX, but it's the kind of dead-tap that makes a sign-in feel broken on first run.
- **Suggested fix:** When `submit()` short-circuits, blur focus and fire a haptic — or better, gate the submit label itself: show `.return` when not submittable.

## Minor — nice to have, defer if needed

### 8. `BlueSkyTemplatesApp.swift` and the `BlueSkyTemplatesApp` *module* share a name

- **Where:** `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift` (struct name) vs `Package.swift:19` (target name).
- **What:** The App struct and its containing module are both `BlueSkyTemplatesApp`. The `App/Sources/AppMain.swift:7,12` `import BlueSkyTemplatesApp` / `BlueSkyTemplatesApp.main()` line works because Swift disambiguates by context, but the shadowing makes the shim file confusing to read at a glance.
- **Suggested fix:** Rename the struct (`AppRoot`, `BSKApp`, or just `Application`). One-line change in the struct, one in the shim. Not load-bearing.

### 9. `EnvironmentKeys.swift` lives in `BlueSkyTemplatesApp` but exposes a `Bluesky` type publicly

- **Where:** `Sources/BlueSkyTemplatesApp/EnvironmentKeys.swift:17` (`public var apiClient: APIClient`).
- **What:** Per §5, only `Bluesky` imports ATProtoKit, and other modules go through `Bluesky`'s public surface. This file is in `BlueSkyTemplatesApp` and adds a public extension to `EnvironmentValues` exposing `APIClient` — which means any other module that imports `BlueSkyTemplatesApp` (none today, but `Compose` will when it's added) inherits the type without importing `Bluesky` directly. That's fine because `Bluesky` *is* the wrapper, but the extension belongs in `Bluesky` so the type and its environment binding live together.
- **Suggested fix:** Move `EnvironmentKeys.swift` to `Sources/Bluesky/`. Either drop the `BlueSkyTemplatesApp` module's dependency on it (it already depends on `Bluesky`), or keep both. Co-locating type and environment key is the convention SwiftUI's own frameworks follow.

### 10. `AppRouter` is dead and `@MainActor`-annotated under main-actor-by-default

- **Where:** `Sources/BlueSkyTemplatesApp/AppRouter.swift:9-12`.
- **What:** The whole file is six lines of placeholder + an `@MainActor` annotation. Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`App/project.yml:24`), `@MainActor` is redundant on every type declared in the package — and indeed nothing else in the codebase repeats it… except this file and `AuthService` (`Sources/Auth/AuthService.swift:12`). Be consistent: drop the annotations or keep them everywhere. (My read of the spec §4 + the project setting argues for dropping them.)
- **Suggested fix:** Either delete `@MainActor` on both `AuthService` and `AppRouter`, or leave them as documentation. Pick one.

### 11. `AuthService`'s convenience init still constructs a one-off `APIClient`

- **Where:** `Sources/Auth/AuthService.swift:41-43` (`self.init(provider: AppPasswordAuth(api: APIClient()))`).
- **What:** This is the "no-arg" init that `AuthService()` would call. The composition root *doesn't* use it (it passes an explicit provider at `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift:28`), but the API leaves the door open for callers to invoke `AuthService()` and get a *third* `APIClient` floating around. It's also a leak of the Bluesky module into Auth's public-init surface — Auth now requires importing Bluesky and Models to *use* this initializer.
- **Why it matters:** Same shape as #1 and #2 — accidental APIClient duplication, smuggled in by a "convenience" that nobody needs.
- **Suggested fix:** Delete the convenience init. There's exactly one composition root; let it own the wiring.

### 12. `errSecSuccess`-only contract in `Keychain.set` will throw on first-write benign codes

- **Where:** `Sources/AppLogging/Keychain.swift:26-27`.
- **What:** `Keychain.set` calls `SecItemDelete` (ignoring the status) and then `SecItemAdd`, then throws unless the status is `errSecSuccess`. This is unused today (the spec calls it out for future DPoP / Share Extension use). Worth noting now while we're looking: `SecItemAdd` on a duplicate (which the preceding `SecItemDelete` may not have caught if the query is too loose) returns `errSecDuplicateItem`. The wrapper turns that into an opaque thrown `Error.status(-25299)`.
- **Why it matters:** Dead code, but it'll bite the first dispatch that uses it.
- **Suggested fix:** Address when the code starts getting used. Flagging it so a later dispatch isn't surprised.

### 13. Asset catalog ships a single 1024×1024 icon — App Store will reject

- **Where:** `App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` + `AppIcon.png`.
- **What:** A single-size icon works for the simulator and Xcode runs, but App Store submission requires multiple sizes and an AppStore marketing slot. Not in scope for Phase 1, but worth recording.
- **Suggested fix:** Defer to the polish phase per spec §11 step 5.

### 14. `Compose`, `DesignSystem`, `Templates` placeholder modules pull in heavy SwiftPM deps they don't use

- **Where:** `Package.swift:52-58` (DesignSystem imports Pow, MarkdownUI, NukeUI), `Package.swift:82-87` (Templates imports DesignSystem transitively).
- **What:** `DesignSystem.swift` is 10 lines of `public enum DesignSystem { static let moduleName = "DesignSystem" }`. The product declarations pull all three external packages into the build graph anyway. Build time isn't great as a result — first `swift build` builds ~900 ATProtoKit + Pow + MarkdownUI + Nuke targets to compile a 10-line file.
- **Why it matters:** Nothing today; it'll matter if anyone has to wait through a cold CI build. Spec §11 step 5 has them needed eventually, but they're literally dead weight in Phase 1.
- **Suggested fix:** Strip the unused product dependencies from `DesignSystem`'s target until they're actually used. Re-add per dispatch that adopts them.

### 15. `LoginView` has no `accessibilityLabel` on the spinner branch and the error `Label` foregroundStyle is `.red` (not semantic)

- **Where:** `Sources/Auth/LoginView.swift:67` (spinner), `Sources/Auth/LoginView.swift:60` (`.foregroundStyle(.red)`).
- **What:** VoiceOver users see "Signing in…" announced (from the visible Text), so the spinner is OK in practice. But `.red` is not a semantic role color — in Dark Mode + high-contrast it's harsh, and on iOS 26 the system prefers `.foregroundStyle(.red)`-via-`Color`. The same issue applies to `HomeView`'s checkmark green and failure red (`Sources/BlueSkyTemplatesApp/HomeView.swift:66, 82`).
- **Suggested fix:** Use `Label(...).labelStyle(.titleAndIcon).foregroundStyle(.red.opacity(...))` or switch to `.tint(.red)` and let the system role color it. Defer to the design-system dispatch.

### 16. Force-unwrap on the help link URL

- **Where:** `Sources/Auth/LoginView.swift:51` (`destination: URL(string: "https://bsky.app/settings/app-passwords")!`).
- **What:** Force-unwrap of a static literal URL. The literal is well-formed, so this won't crash — but the spec / Swift guidelines argue for `URL(string:)!` only when an invariant comment explains why. Trivial enough to defer.
- **Suggested fix:** `URL(static: "...")` (iOS 16+) or a `static let` declaration with a comment. Or leave it.

### 17. `RootView` doesn't react to `.task` cancellation during `restore()`

- **Where:** `Sources/BlueSkyTemplatesApp/RootView.swift:26` (`.task { await auth.restore() }`).
- **What:** If the view is torn down (e.g. scene phase background) during `.restoring`, the `Task` is cancelled but `AuthService` keeps its `.restoring` state. On the way back the UI shows the splash indefinitely.
- **Why it matters:** Edge case, but possible during cold-launch into a quick task-switch.
- **Suggested fix:** Add a `defer { if case .restoring = state { state = .signedOut } }`-equivalent inside `AuthService.restore()`, or check `Task.isCancelled` and reset.

## Spec adherence checklist

| Spec section | Status | Note |
|---|---|---|
| §4 target stack | ✅ | iOS 26, Swift 6.2 (`Package.swift:1` + `App/project.yml:21-27`), `@Observable`, SwiftData, no ViewModels, native `SecItem` wrapper, `os.Logger`, Liquid Glass via system controls. `SWIFT_VERSION` is "6.0" in `project.yml:21` not "6.2" — that's the language mode (Swift 6 = strict concurrency), with 6.2-toolchain settings layered on; correct. |
| §5 module layout | ✅ | Modules exactly as prescribed; `Bluesky` is the only ATProtoKit importer (`Sources/Bluesky/APIClient.swift:13` is the sole hit). Module named `AppLogging` instead of `Logging` to avoid swift-log collision — sensible deviation noted in `Package.swift:42-43`. |
| §6.1 canonical screen shape | ⚠️ | App composition root present (`Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift`) but constructs two `APIClient`s (Critical #1). Service shapes (`actor` + `@Observable`) correct. View-without-VM and enum-typed LoadState correct in `LoginView` / `HomeView`. |
| §6.3 AsyncStream auth lifecycle | ⏭️ | Out of scope for Phase 1.2 per the user — current `AuthService` mutates `state` directly. Acceptable now; will need the stream when multiple subscribers care (background refresh, deep-link auth). |
| §6.4 logging | ✅ | `Sources/AppLogging/Log.swift` has the four categories; every interpolation of secret-shaped data carries a privacy specifier (`Sources/Bluesky/APIClient.swift:152`). No `print()`. `OSSignposter` not used yet — not required for Phase 1. |
| §6.5 SwiftData | ✅ | `@Model Template` at `Sources/Templates/Template.swift:11`, container wired in `Sources/BlueSkyTemplatesApp/BlueSkyTemplatesApp.swift:38`, no `save()`. V1→SwiftData migration is correctly deferred to the Templates port dispatch. |
| §7.2 AuthProvider | ⚠️ | Protocol shape matches the spec almost exactly — but inherits the same leaky `refresh(_:)` parameter the prior dispatch flagged. `AppPasswordAuth.refresh` ignores it (`Sources/Auth/AppPasswordAuth.swift:25`) and `AuthService.restore()` fakes a sentinel `SessionInfo` to call it (`Sources/Auth/AuthService.swift:67`). See Important #3 — the spec needs updating *and* the code should split the protocol. |
| §8.1 version pin | ✅ | `Package.swift:30-31` pins `0.32.5..<0.33.0` exactly as specified. |
| §8.2 auth path | ✅ | `AppleSecureKeychain(identifier:, serviceName:)` per spec, UUID persisted in UserDefaults (handle not secret), `cfg.authenticate(with:password:)` + `cfg.refreshSession()` + `cfg.deleteSession()`. Service name `com.dtolb.BlueSkyTemplates` matches bundle id. |
| §8.3 post path | ⏭️ | Only `postHelloWorld()` exists (`Sources/Bluesky/APIClient.swift:123`). Full facets/images/alt/aspect/lang path is the next dispatch — appropriate Phase 1 scope. |
| §8.4 known-gap mitigations | ⚠️ | `@preconcurrency` ✅. **No `@unchecked @retroactive Sendable` extension on `ATProtoKit`** — the spec said we'd need it; we don't, because the actor isolation model + `@preconcurrency` is enough at 0.32.5 under our config. That's a finding worth recording (and the spec should drop that mitigation). PDS discovery / `ATResolve` is not wired — only `bsky.social` works today. Phase 1 acceptable. |
| §9 supporting libs | ⚠️ | All four deps pinned correctly (`Package.swift:30-37`). Pow uses `from: "1.0.6"` not `.upToNextMajor` (functionally equivalent; nit). Pow / MarkdownUI / NukeUI are listed as `DesignSystem` dependencies and pulled into the build graph even though unused (Minor #14). |
| §13 cheatsheet (bans) | ✅ | No `print()`, no `MainActor.run`, no `ObservableObject` family, no `@StateObject` / `@ObservedObject` / `@Published` / `@EnvironmentObject`, no ViewModels, no `KeychainAccess`, no JSON-in-UserDefaults for user content. Only legitimate UserDefaults use is the keychain UUID handle (`Sources/Bluesky/APIClient.swift:40-44`) — that's not user content. Clean sweep. |

## Test quality assessment

**Genuinely good for Phase 1, and the right shape per §4's "test state transitions, not view bodies."** The 15 tests:

- `AuthSurfaceTests` (2): basic surface — startup state, `SessionInfo` Hashable/Sendable. Tautological-ish but cheap. ✅
- `AuthServiceStateTests` (6): every `AuthService.State` transition. **These are not tautological** — they exercise `signIn-success → signedIn`, `signIn-failure → error`, `dismissError → signedOut`, `restore-failure → signedOut`, `restore-success → signedIn`, `signOut → signedOut`. The `MockAuthProvider` is realistic enough: it's an `actor` with scripted outcomes and call counters. ✅
- `HandleNormalizationTests` (5): plain, leading-`@`, trailing-newline, multiple-`@`, mixed case. ✅
- `TemplateModelTests` (1): trivial init test. ⚠️ Not really pulling its weight.
- `ComposeModuleTests` (1): asserts `ComposeFeature.moduleName == "Compose"`. **Tautological** — the module itself is the placeholder. ⚠️

**What's missing (in priority order):**

1. **Edge cases in `bskyNormalizedHandle`**: empty string, single `@`, `@@@` only (no domain), unicode characters in handle, whitespace-only input. Five lines each, would catch a regression where someone "fixes" the `drop(while:)` to a single `dropFirst()`.
2. **`AuthService.restore()` when provider throws an unexpected error** (not `APIError.notAuthenticated`) — does it still land at `.signedOut`? Yes per the implementation (`Sources/Auth/AuthService.swift:70-73` swallows any throw), but the test only proves it for `APIError.notAuthenticated`. Pin the broader contract.
3. **`signOut()` from `.signingIn`** — what happens? Today the guard at `Sources/Auth/AuthService.swift:77` says "anything that's not `.signedIn` short-circuits to `.signedOut`." Tested for `.error`-after-failed-signIn but not for the racy mid-signIn case.
4. **`MockAuthProvider.revokeCalls`** — counter exists, never asserted. The sign-out test (`Tests/AuthTests/AuthTests.swift:157-165`) should `#expect(provider.revokeCalls == 1)` to prove the revoke actually fired before the local state cleared. Otherwise we don't know whether sign-out is calling the network at all.
5. **`SessionInfo` round-trip via JSON** — it's `Codable`. Cheap to pin.
6. The `BlueskyTests` target needs to grow into a real boundary-testing surface for `APIClient` errors (`postHelloWorld` without authentication should throw `.notAuthenticated`) — today it only tests the string extension.

`TemplateModelTests` and `ComposeModuleTests` are placeholder-grade; they should grow when those features land. Not a merge blocker.

## Verification

```
$ swift build
... 916 targets compiled cleanly ...
Build complete! (18.28s)
```
Zero warnings, zero errors. Full clean build (`swift package clean && swift build`) of the entire dependency graph including ATProtoKit (~900 lexicon files), Nuke, Pow, swift-markdown-ui.

```
$ swift test
✔ Test run with 15 tests in 5 suites passed after 0.001 seconds.
```
15/15 pass. Test runtime well under a second.

```
$ cd App && xcodegen generate && xcodebuild build \
    -project BlueSkyTemplates.xcodeproj -scheme BlueSkyTemplates \
    -destination 'platform=iOS Simulator,name=iPhone 17'
...
2026-05-20 23:13:52.067 appintentsmetadataprocessor[26627]:
  warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```
Historical note: at this review point the app did not ship App Intents, so
Apple's `appintentsmetadataprocessor` warning was harmless. Phase J later
added a narrow `CreateTemplateIntent` and app shortcut metadata.

## Recommendation

**Merge after Critical (#1 and #2).**

Both Critical items are one-file, low-line-count fixes: drop the redundant `@State private var api = APIClient()` initializer in the App, and either nil-default or precondition-default the `APIClientKey`. They're the only two issues that could quietly grow into real bugs if left in place. Everything else in the Important / Minor sections can ride on follow-up dispatches without regret — the foundation is sound and the spec is being honored where it matters most (module boundaries, isolation model, logging, no banned patterns).

The spec itself should be updated based on what landed:

- §7.2's `refresh(_ session:)` protocol shape is wrong; record the split into `restore()` + `refresh(_:)` (Important #3).
- §8.4 should drop the `@unchecked @retroactive Sendable` mitigation — at 0.32.5 with `@preconcurrency` and our isolation model it isn't needed.
- §9.4 should note that the access-group entitlement migration is now deferred (see `App/project.yml:73-75` comment), not configured up front.
