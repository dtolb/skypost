# BlueSkyTemplates — Next Steps (May 20, 2026)

> Foundation doc. Synthesis of a v1 audit and five parallel research agents
> (ATProtoKit deep dive, IcySky reference architecture, Bluesky OAuth on
> iOS, modern Apple SwiftUI patterns, supporting libraries). This is the
> opinionated source of truth for v2 and for how Dan builds Swift/iOS apps
> going forward.
>
> Date stamp: 2026-05-20. Re-evaluate annually around WWDC and whenever
> ATProtoKit hits 1.0 or ships OAuth.

---

## 1. TL;DR

- **Start over.** v1 is ~2,860 lines of stitched SwiftUI from one day in
  March 2025. The security model (plaintext password in `UserDefaults`),
  the API correctness (no facets for mentions/URLs, hardcoded PDS, no alt
  text, NSRange grapheme bug), and the architecture (3 view models each
  with their own `BlueSkyService` instance) all converge on the same
  rewrite.
- **Port three things from v1:** `Template` model, `TemplateService` JSON
  CRUD (then upgrade to SwiftData), and the `.gitlab-ci.yml`. Everything
  else is rewritten.
- **Target stack:** iOS 26 minimum, Swift 6.2 with Approachable
  Concurrency, `@Observable` everywhere, SwiftData for templates,
  ASWebAuthenticationSession for OAuth when it lands, native `SecItem`
  wrapper for Keychain, `os.Logger` with privacy specifiers — `print()`
  banned.
- **Bluesky SDK:** ATProtoKit pinned to **0.32.5** (`.upToNextMinor`,
  bounded `< 0.33`). Yellow-light: pre-1.0, no OAuth yet, but kills v1's
  biggest bugs and is the only credible Swift atproto client.
- **Auth strategy for v2:** ship app passwords behind an `AuthProvider`
  protocol so OAuth swaps in cleanly later. **Do not gate v2 on OAuth** —
  the 2-week public-client session ceiling means OAuth offers no UX
  improvement over app passwords for a personal app today.
- **No ViewModels.** Services are `@Observable`, views consume them via
  `@Environment(Service.self)`, local UI state is `@State` (often an
  enum). This is the IcySky pattern, and it's correct for v2.
- **Supporting libs (pinned):** Nuke 13.0.6, Pow 1.0.6, MarkdownUI 2.4.1.
  **Skip:** Textual (pre-1.0, known perf bugs), KeychainAccess (stale +
  blocks App Extensions; write the 80-line native wrapper instead),
  ObservableObject patterns, ViewInspector.

---

## 2. v1 Audit — the rationale for starting over

### 🔴 Security (App Store blocker)
- Plaintext password persisted in `UserDefaults` via `BlueSkyAuth` Codable
  serialization (`Services/BlueSkyService.swift:32-38`).
- `accessJwt` / `refreshJwt` also in UserDefaults (unencrypted plist).
- Password held in memory after session creation with no reason to.

### 🟠 Bluesky correctness
- Hardcoded `https://bsky.social` — no PDS discovery via DID.
- Facets only for hashtags — URLs and `@mentions` won't render as links.
- All images uploaded with the literal alt text `"Image uploaded from
  BlueSkyTemplates app"`.
- No `langs`, no `aspectRatio` on image embeds.
- `NSRange(location: 0, length: text.count)` in `parseHashtags` uses
  grapheme count instead of `text.utf16.count` — emoji in posts mis-index
  or crash.

### 🟠 Architecture
- `AuthViewModel`, `PostViewModel`, `TemplatesViewModel` each
  `init()` their own `BlueSkyService()` — three independent in-memory
  auth states.
- `PostViewModel.login()` duplicates `AuthViewModel.login()` — only one
  updates `isLoggedIn`.
- `[String: Any]` JSON throughout — no Codable request/response types.
- No protocols, no test target, no DI.

### 🟡 Code smells (LLM-stitch signature)
- Two near-duplicate image-resize functions in `BlueSkyService`, plus a
  third in `PhotoService` — only one is called.
- Used resize uses deprecated `UIGraphicsBeginImageContextWithOptions`;
  the *unused* one uses the modern `UIGraphicsImageRenderer`.
- `do { ... }` with no `try` and no `catch` in `PostViewModel.submitPost`.
- `print(...)` dumps full post payloads — including JWT — on every post.
- `PostViewModel` not `@MainActor` while sibling `AuthViewModel` is.

### 🟡 Hygiene
- `BlueSkyTemplates/api.json` (25,333 lines) + two `.mdx` files are
  committed Bluesky reference docs, unused by the app, ~94 % of the repo.
- No SPM, no SwiftLint/swift-format.
- No tests; CI runs `xcodebuild build` only (TODO at top of
  `.gitlab-ci.yml:1-6` acknowledges this).

### Decision

The rewrite is cheaper than the cleanup. Fixing the auth model rewrites
`BlueSkyAuth`, `BlueSkyService.login/refresh/save`, and `AuthViewModel` —
~30% of the code. Fixing Bluesky correctness rewrites most of the rest of
`BlueSkyService` — and ATProtoKit does it for us. Once both are done the
view models exist only to wrap `@Published`, which on iOS 17+ with
`@Observable` you don't need.

---

## 3. What to port from v1

- `Models/Template.swift` (clean, small, correct — upgrade to `@Model`)
- `Services/TemplateService.swift` (UserDefaults CRUD — replace store
  with SwiftData; keep the API shape as inspiration)
- `.gitlab-ci.yml` (just got it green on the `xcode` runner; add the
  test conversion the file's own TODO describes)
- `FlowLayout` (works, reuse as-is)
- Product concept itself

Throw away everything else.

---

## 4. v2 target stack

| Dimension | Choice | Why |
|---|---|---|
| iOS minimum | **iOS 26** | Liquid Glass, refined `AttributedString`, Swift 6.2 approachable concurrency, ~74% install base by Feb 2026, ~81%+ by Apr 2026. For a personal app the install-base argument doesn't apply; we get the modern idiom for free. |
| Language | **Swift 6.2**, Approachable Concurrency | `SWIFT_VERSION = 6` + `DefaultIsolation = MainActor` + `NonisolatedNonsendingByDefault`. Main-by-default kills v1's `MainActor.run` sprinkles. |
| Observation | **`@Observable` macro** everywhere | Per-property tracking. `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject` banned in v2. |
| View architecture | **No ViewModels.** `@Environment` for services, `@State` (often an enum) for UI state, `.task` for async. IcySky's pattern, confirmed by the modern-patterns research. |
| Persistence (user content) | **SwiftData + private CloudKit** | `@Query` integrates natively. `TemplateStorage` owns the schema/config and uses `iCloud.com.dtolb.BlueSkyTemplates` for synced templates with a local fallback. |
| Persistence (settings) | UserDefaults | Theme, last-selected feed, "v2_migration_done" flag. Never user content. |
| Navigation | `NavigationStack(path:)` + `.navigationDestination(for:)` + one `@Observable Router` per tab. `.sheet` for in-flow modals; `.fullScreenCover` for task takeovers. |
| Async work | `.task` / `.task(id:)` for view-scoped, `async let` for parallel. Never `.onAppear { Task { } }`. Never `MainActor.run`. |
| Service layer | `actor` for network/IO; `@Observable` class for state holding. All DTOs `Sendable, Hashable, Codable`. |
| Auth (now) | App passwords through ATProtoKit's `ATProtocolConfiguration` + `AppleSecureKeychain` (built into ATProtoKit). Wrapped behind an `AuthProvider` protocol so OAuth can swap in. |
| Auth (eventual) | atproto OAuth via `ASWebAuthenticationSession` + DPoP. Wait for ATProtoKit's OAuth module; fall back to ChimeHQ/OAuthenticator + jose-swift if we need it sooner. |
| Keychain | **Native `SecItem` wrapper** (~80 lines), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Configure access-group entitlement up front. |
| Logging | `os.Logger` per subsystem+category, privacy specifiers (`.public` / `.private` / `.private(mask: .hash)`). `print()` banned. |
| Liquid Glass | System controls get it free. `.buttonStyle(.glass)` by default. `.glassEffect` / `GlassEffectContainer` for custom overlays only. |
| Color surfaces | `BrandColor.pageBackground` for screen backgrounds; `BrandColor.cardBackground` for cards/lists. `LeadIcon` adapts its fill/glyph by color scheme. Avoid hard-coded `Color.white`/`Color.black` UI surfaces outside brand-filled contexts. |
| Testing | **Swift Testing** (`@Test` / `#expect`). Test `@Observable` state transitions, not view bodies. XCTest only for `XCUIApplication`. Skip ViewInspector. |
| Dependencies | ATProtoKit, Nuke + NukeUI, Pow, MarkdownUI. **Nothing else.** Apple-native first. |
| Tooling | SwiftPM-driven project, SwiftLint with a `no_print` rule, swift-format. |

---

## 5. Module layout (IcySky-inspired, scaled down)

IcySky uses **two top-level SPM packages** (Features + Model) with internal
sub-modules. For a single-screen poster this is overkill; collapse to:

```
BlueSkyTemplatesV2/
├── Package.swift                  # SPM workspace
├── Sources/
│   ├── BlueSkyTemplatesApp/       # @main + composition root + Router
│   ├── DesignSystem/              # tokens, colors, internal Buttons/Cards
│   ├── Auth/                      # AuthProvider protocol + AppPasswordAuth impl
│   ├── Bluesky/                   # BSkyClient wrapping ATProtoKit + ATProtoBluesky
│   ├── Models/                    # Sendable DTOs (SessionInfo, Facet, etc.)
│   ├── Templates/                 # @Model Template + SwiftData queries + JSON exchange
│   ├── Compose/                   # Composer screen + facet parsing helper
│   └── Logging/                   # os.Logger setup, privacy helpers
├── Tests/
│   ├── ComposeTests/              # facet parsing, length limit, hashtag extraction
│   ├── TemplatesTests/            # SwiftData round-trip
│   └── AuthTests/                 # AuthProvider mock + token refresh
├── App/                           # Xcode project shell (for entitlements + asset catalog)
└── .gitlab-ci.yml                 # ported from v1
```

Module ownership rules from IcySky's good ideas, minus its anti-patterns:
- **`Bluesky` module is the only thing that imports ATProtoKit.** All UI
  modules talk to `BSkyClient` (our wrapper), not ATProtoKit directly.
  IcySky's biggest sin is leaking `@preconcurrency import ATProtoKit` into
  every view file — don't replicate.
- **`Auth` exposes a protocol;** `AppPasswordAuth` is the only
  implementation at v2 launch. When OAuth lands, add `OAuthAuth` next to
  it, swap in the composition root, ship.
- **`DesignSystem` has no dependency on Models or Bluesky.** It's pure
  presentation. IcySky's DesignSystem is 380 lines; ours will be smaller.
- **`Compose` and `Templates` are SwiftUI feature modules** that depend
  only on `Bluesky`, `Auth`, `Models`, `Templates` (SwiftData models live
  here), and `DesignSystem`.

---

## 6. Architecture & patterns

### 6.1 The canonical screen shape (memorize this)

```swift
// ──────────────────────────────────────────────────────────────
// App composition root — long-lived services as @State on App
// ──────────────────────────────────────────────────────────────
@main
struct BlueSkyTemplatesApp: App {
    @State private var auth = AuthService()
    @State private var router = AppRouter()
    @State private var templateModelContainer = try! TemplateStorage.makeCloudContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(router)
        }
        .modelContainer(templateModelContainer)
    }
}

// ──────────────────────────────────────────────────────────────
// An @Observable service — main-isolated by default under
// Swift 6.2 Approachable Concurrency.
// ──────────────────────────────────────────────────────────────
@Observable
final class AuthService {
    enum State { case signedOut, signedIn(SessionInfo), error(Error) }
    private(set) var state: State = .signedOut

    private let api = APIClient()                    // actor — off main

    func signIn(handle: String, appPassword: String) async {
        do {
            let session = try await api.authenticate(handle: handle, password: appPassword)
            state = .signedIn(session)
        } catch {
            state = .error(error)
        }
    }
}

// ──────────────────────────────────────────────────────────────
// Service actor — owns the network. Returns Sendable values.
// No MainActor.run, ever.
// ──────────────────────────────────────────────────────────────
actor APIClient {
    func authenticate(handle: String, password: String) async throws -> SessionInfo {
        // ATProtoKit work happens here
    }
}

struct SessionInfo: Sendable, Hashable {
    let did: String
    // never log directly — see logging section
}

// ──────────────────────────────────────────────────────────────
// A screen — no ViewModel. Local enum drives loading UI.
// ──────────────────────────────────────────────────────────────
struct TemplateListView: View {
    @Environment(AuthService.self) private var auth
    @Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]
    @State private var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle, loading, failed(String)
    }

    var body: some View {
        List(templates) { TemplateRow(template: $0) }
            .navigationTitle("Templates")
            .task { await refresh() }                 // free cancellation on disappear
            .refreshable { await refresh() }
            .overlay { if case .failed(let msg) = loadState { ErrorView(msg) } }
    }

    private func refresh() async {
        loadState = .loading
        // …
        loadState = .idle
    }
}
```

### 6.2 The paginated-list pattern (steal from IcySky verbatim)

For any feed/timeline/notification list:

```swift
// State enum — total exhaustivity
enum PostsListViewState: Sendable {
    case uninitialized
    case loading
    case loaded(posts: [PostItem], cursor: String?)
    case error(Error)
}

// Datasource protocol — view conforms to it as itself
@MainActor
protocol PostsListViewDatasource {
    var title: String { get }
    func loadPosts(with state: PostsListViewState) async -> PostsListViewState
}

// Reusable list — switches on state, drives pagination
struct PostListView<DS: PostsListViewDatasource>: View {
    let datasource: DS
    @State private var state: PostsListViewState = .uninitialized

    var body: some View {
        List {
            switch state {
            case .loading, .uninitialized: placeholderView
            case .loaded(let posts, let cursor):
                ForEach(posts) { PostRowView(post: $0) }
                if cursor != nil {
                    Color.clear.task { state = await datasource.loadPosts(with: state) }
                }
            case .error(let error): Text(error.localizedDescription)
            }
        }
        .task { if case .uninitialized = state {
            state = .loading
            state = await datasource.loadPosts(with: state)
        }}
        .refreshable {
            state = .loading
            state = await datasource.loadPosts(with: state)
        }
    }
}
```

The genius: `loadPosts(with: currentState) -> nextState`. Pagination,
retry, and initial load are one function. State transitions are pure-ish
and statically exhaustive.

### 6.3 Auth lifecycle via `AsyncStream` (steal from IcySky)

```swift
@Observable
final class Auth: @unchecked Sendable {
    var configuration: ATProtocolConfiguration?
    let configurationUpdates: AsyncStream<ATProtocolConfiguration?>
    private var continuation: AsyncStream<ATProtocolConfiguration?>.Continuation!

    init() {
        var c: AsyncStream<ATProtocolConfiguration?>.Continuation!
        self.configurationUpdates = AsyncStream { c = $0 }
        self.continuation = c
    }

    func authenticate(handle: String, appPassword: String) async throws {
        let cfg = ATProtocolConfiguration(keychainProtocol: ATProtoKeychain.shared)
        try await cfg.authenticate(with: handle, password: appPassword)
        self.configuration = cfg
        continuation.yield(cfg)
    }

    func refresh() async {
        let cfg = ATProtocolConfiguration(keychainProtocol: ATProtoKeychain.shared)
        do {
            try await cfg.refreshSession()
            self.configuration = cfg
            continuation.yield(cfg)
        } catch {
            self.configuration = nil
            continuation.yield(nil)
        }
    }

    func logout() async throws {
        try await configuration?.deleteSession()
        configuration = nil
        continuation.yield(nil)
    }
}
```

All four state transitions (boot/login/refresh/logout) ride the same
stream. The App-level `.task` consumes it and flips `AppState` between
`.authenticated(client, currentUser)` and `.unauthenticated`. **One
funnel, one place to mutate `AppState`.**

### 6.4 Logging template (replaces v1's `print(jwt)`)

```swift
// Sources/Logging/Log.swift
import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tolbnet.bsktemplates"

    static let auth    = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let ui      = Logger(subsystem: subsystem, category: "ui")
}
```

Usage rules:

```swift
Log.network.info("Request → \(url.absoluteString, privacy: .public)")
Log.auth.debug("Refreshed token for did=\(did, privacy: .private(mask: .hash))")
Log.auth.info("Got access token \(token, privacy: .private(mask: .hash))")
Log.network.error("HTTP \(code, privacy: .public) on \(endpoint, privacy: .public): \(body, privacy: .private)")
```

Hard rules:
1. `print()` is banned in shipped code. SwiftLint enforces.
2. No string interpolation of tokens without an explicit privacy specifier.
3. Logger categories match module names.
4. `.debug`/`.info` are stripped in release. Use `.notice`/`.error`/`.fault` for production-visible.
5. `OSSignposter` for performance traces (OAuth flow, image loading, list rendering).

### 6.5 SwiftData pattern

```swift
@Model
final class Template {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var hashtags: [String] = []
    var updatedAt: Date = .now

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        hashtags: [String] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.hashtags = hashtags
        self.updatedAt = updatedAt
    }
}
```

```swift
// App level
.modelContainer(templateModelContainer)

// View level
@Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]
@Environment(\.modelContext) private var modelContext

// Save explicitly after user-initiated creates, edits, deletes, and JSON imports
// so UI flows and tests have deterministic persistence boundaries.
// One-time migration on first launch:
if !UserDefaults.standard.bool(forKey: "v2_migration_done") {
    if let old = UserDefaults.standard.data(forKey: "saved_templates"),
       let v1Templates = try? JSONDecoder().decode([V1Template].self, from: old) {
        for t in v1Templates {
            modelContext.insert(Template(title: t.name, body: t.text, hashtags: t.hashtags))
        }
        UserDefaults.standard.set(true, forKey: "v2_migration_done")
        UserDefaults.standard.removeObject(forKey: "saved_templates")
    }
}
```

CloudKit-backed SwiftData cannot enforce `@Attribute(.unique)` for the
template UUID. Imports therefore upsert manually by `Template.id` through
`TemplateExchange.upsert(_:into:)`, deleting duplicate rows if a local
store ever contains more than one row for the same UUID.

`TemplateStorage` is the single place that creates the template schema
and model containers:

- `TemplateStorage.makeCloudContainer()` uses private CloudKit container
  `iCloud.com.dtolb.BlueSkyTemplates`.
- `TemplateStorage.makeInMemoryContainer()` disables CloudKit for tests
  and previews.

`TemplateExchange` owns versioned JSON import/export for user-visible
template sharing. Single-template JSON and archives both decode into
stable template documents.

---

## 7. Authentication strategy

### 7.1 Verdict: no OAuth in v2. Ship app passwords behind an abstraction.

Three reasons (full reasoning in the OAuth research report):

1. **ATProtoKit doesn't ship OAuth yet.** Issue #43 has been open since
   Oct 2024. The maintainer's standalone `ATOAuthKit` repo has zero
   commits since Aug 2025. The only credible alternative is
   ChimeHQ/OAuthenticator + jose-swift, which puts ~600 lines of
   security-critical code (PAR + DPoP + nonce cache + JWT signing + key
   lifecycle + identity verification) under our maintenance.
2. **The 2-week public-client session ceiling** means OAuth gives v2
   users *worse* persistence than app passwords. Public clients (anything
   without a confidential backend) get 2-week refresh tokens.
3. **Migration cost is bounded.** A clean `AuthProvider` protocol means
   the swap is one impl, no UI changes.

### 7.2 The `AuthProvider` protocol

```swift
// Sources/Auth/AuthProvider.swift
protocol AuthProvider: Sendable {
    func session(handle: String, secret: String?) async throws -> ATProtoSession
    func refresh(_ session: ATProtoSession) async throws -> ATProtoSession
    func revoke(_ session: ATProtoSession) async throws
}

struct AppPasswordAuth: AuthProvider {
    // wraps ATProtocolConfiguration.authenticate(with:password:)
}

// Future:
// struct OAuthAuth: AuthProvider {
//     // wraps ASWebAuthenticationSession + ChimeHQ/OAuthenticator (or
//     // ATProtoKit OAuth when it lands)
// }
```

UI calls `auth.session(handle:, secret:)`. App-password flow asks the user
for a password; OAuth flow ignores `secret` and opens
`ASWebAuthenticationSession`. The UI is identical — the secret prompt is
the only thing that changes.

### 7.3 Triggers for migrating to OAuth

In order of preference:
1. `MasterJ93/ATProtoKit` ships an `OAuth` module → use it.
2. `ChimeHQ/OAuthenticator` reaches v1.0 → wrap it, document the switch.
3. Bluesky announces an app-password deprecation date → start the work
   immediately regardless of the above.

When the trigger fires, the migration is: implement `OAuthAuth`, host
`client-metadata.json` on GitHub Pages (or
`bsky-templates.tolb.blue/client-metadata.json` if we want a nicer
authorization screen), register `com.tolb.bskytemplates` URL scheme in
`Info.plist`, swap the impl in the composition root, ship.

### 7.4 OAuth integration plan (for the day it lands)

When we do migrate, the full flow:

```
[User taps "Sign in with Bluesky"]
        v
[Handle resolution: DNS TXT / .well-known/atproto-did → DID → PDS endpoint]
        v
[PDS metadata fetch: .well-known/oauth-protected-resource → auth server metadata]
        v
[Per-session DPoP key gen: CryptoKit.P256.Signing.PrivateKey(), Keychain]
        v
[PKCE: verifier = random(64), challenge = base64url(SHA256(verifier))]
        v
[PAR: POST par_endpoint → request_uri]
        v
[ASWebAuthenticationSession to auth_endpoint?client_id=...&request_uri=...]
        v
[Redirect callback: com.tolb.bskytemplates:/callback?code=...&state=...&iss=...]
        v
[Token exchange: POST token_endpoint with DPoP JWT, retry with nonce on 400]
        v
[Verify identity: re-resolve sub (DID) → confirm PDS == auth-server origin]
        v
[Store: access_token, refresh_token, DPoP key, sub, issuer, scope in Keychain]
        v
[Every API call: Authorization: DPoP <access>; DPoP: <fresh JWT with ath=hash(access)>]
```

Key facts for v2's eventual OAuth migration (from the OAuth research):

- **Redirect URI format:** `com.tolb.bskytemplates:/callback` (single
  colon + single slash + path). `com.tolb.bskytemplates://callback`
  (double slash) is **rejected** by the server. This bit native-app
  developers hard pre-2024.
- **`client_id` is a URL the server fetches.** Host
  `client-metadata.json` on GitHub Pages or your own domain. The
  `client_id` value must equal the URL exactly (case-sensitive).
- **Minimum metadata for a public native client:**
  ```json
  {
    "client_id": "https://dtolb.github.io/bskytemplates/client-metadata.json",
    "application_type": "native",
    "client_name": "BSky Templates",
    "client_uri": "https://dtolb.github.io/bskytemplates",
    "grant_types": ["authorization_code", "refresh_token"],
    "scope": "atproto transition:generic",
    "response_types": ["code"],
    "redirect_uris": ["com.tolb.bskytemplates:/callback"],
    "token_endpoint_auth_method": "none",
    "dpop_bound_access_tokens": true
  }
  ```
- **DPoP keys:** ES256 (P-256), stored in Keychain (not Secure Enclave —
  SE keys can't sync via iCloud Keychain, which forces re-login on device
  migration; the 2-week refresh ceiling already caps damage). Use
  CryptoKit for signing, jose-swift or hand-rolled JWS compact
  serialization for the envelope.
- **ASWebAuthenticationSession:** `prefersEphemeralWebBrowserSession =
  true`. Users authenticating to *a PDS account* should not reuse Safari
  cookies; the cost of typing a password is acceptable since we'll store
  the resulting tokens anyway.
- **Token exchange retry:** First call returns 400 + `DPoP-Nonce` header;
  retry with the nonce baked into the DPoP JWT. Cache the nonce for
  subsequent requests.

---

## 8. ATProtoKit integration

### 8.1 Version pin

```swift
.package(url: "https://github.com/MasterJ93/ATProtoKit.git",
         .upToNextMinor(from: "0.32.5"))
```

**Why `.upToNextMinor`:** every 0.32.x patch since Sep 2025 has been
lexicon model / decoder fixes for real bugs. **Why `<0.33`:** the 0.26
and 0.31 minor bumps had breaking changes (init signatures changed,
`ensureValidToken()` semantics changed). The maintainer explicitly warns
"things will break" until 1.0.

Platform minimums: iOS 14 / macOS 13. Our v2 target (iOS 26) is well
above.

### 8.2 Auth path (app password)

```swift
import ATProtoKit
@preconcurrency import struct ATProtoKit.AppleSecureKeychain

final class BlueskyAuth: @unchecked Sendable {
    private let keychain: AppleSecureKeychain
    private(set) var config: ATProtocolConfiguration?
    private(set) var bsky: ATProtoBluesky?
    private(set) var protoKit: ATProtoKit?

    init() {
        // Persist UUID across launches. The UUID is a *handle* to the keychain
        // bundle — the real secrets (refresh token, app password) live there.
        let stored = UserDefaults.standard.string(forKey: "bsky.keychainUUID")
        let uuid = stored.flatMap(UUID.init(uuidString:)) ?? UUID()
        if stored == nil {
            UserDefaults.standard.set(uuid.uuidString, forKey: "bsky.keychainUUID")
        }
        self.keychain = AppleSecureKeychain(
            identifier: uuid,
            serviceName: "com.dtolb.BlueSkyTemplates"
        )
    }

    func signIn(handle: String, appPassword: String) async throws {
        let cfg = ATProtocolConfiguration(keychainProtocol: keychain)
        try await cfg.authenticate(with: handle, password: appPassword)
        let kit = await ATProtoKit(sessionConfiguration: cfg)
        self.config = cfg
        self.protoKit = kit
        self.bsky = ATProtoBluesky(atProtoKitInstance: kit)
    }

    // Call at app launch — succeeds if refresh token in Keychain is still valid.
    func restore() async throws {
        let cfg = ATProtocolConfiguration(keychainProtocol: keychain)
        try await cfg.refreshSession()
        let kit = await ATProtoKit(sessionConfiguration: cfg)
        self.config = cfg
        self.protoKit = kit
        self.bsky = ATProtoBluesky(atProtoKitInstance: kit)
    }

    func signOut() async throws {
        try await config?.deleteSession()
        config = nil; bsky = nil; protoKit = nil
    }
}
```

**What we get for free:**
- `AppleSecureKeychain` writes the refresh token + app password into the
  Keychain and keeps the access token in memory only. Kills the v1
  plaintext-password-in-UserDefaults bug entirely.
- Access token expiry is checked before every authenticated request by
  `prepareAuthorizationValue` → `ensureValidToken()`. If expired, it
  transparently calls `refreshSession()`. This includes `createRecord` —
  i.e. posting auto-refreshes. (Broken before 0.31.0 — issue #203.)
- 2FA via an `AsyncStream<String>`: call
  `config.receiveCodeFromUser("123456")` from the UI when the auth call
  blocks on a code prompt.

### 8.3 Post path (text + image + facets + alt + aspect + lang)

```swift
import ATProtoKit
import UIKit

func postWithImages(
    bsky: ATProtoBluesky,
    text: String,
    images: [(data: Data, alt: String, size: CGSize)],
    languages: [Locale] = [Locale(identifier: "en")]
) async throws -> ComAtprotoLexicon.Repository.StrongReference {
    let imageQueries = images.map { img in
        ATProtoTools.ImageQuery(
            imageData: img.data,             // ≤ 1 MB, JPEG. Resize + JPEG-encode upstream.
            fileName: "image_\(UUID().uuidString).jpg",
            altText: img.alt,
            aspectRatio: .init(width: Int(img.size.width),
                               height: Int(img.size.height))
        )
    }

    return try await bsky.createPostRecord(
        text: text,                          // facets auto-parsed (mentions/URLs/hashtags)
        inlineFacets: nil,                   // [(URL, utf8Start, utf8End)] for anchored hyperlinks
        locales: languages,
        replyTo: nil,
        embed: .images(images: imageQueries),
        labels: nil,
        tags: nil,
        creationDate: Date()
    )
}
```

**What `createPostRecord` does for us (`CreatePostRecord.swift:332-586`):**
- Calls `ATFacetParser.parseFacets(from:pdsURL:)` to auto-build mention,
  URL, and hashtag facets in **UTF-8 byte offsets** — this fixes v1's
  NSRange/grapheme bug.
- Mentions go through `resolveHandle` to attach the DID.
- `truncateAndReplaceLinks` rewrites long URLs and re-anchors facet byte
  ranges. Anything >32 chars after scheme strip gets `…` appended.
- Truncates to 300 chars via `resolvedText.truncated(toLength: 300)`.
  301st char onward is silently dropped — validate length yourself in the
  composer for UX.
- Uploads each image as a blob via `uploadBlob`, builds the embed.
  **Hard 1 MB per image limit** (throws `ATBlueskyError.imageTooLarge`);
  max 4 images; JPEG-only.
- Locales on iOS 16+ use `locale.language.languageCode?.identifier`.

### 8.4 Known gaps + workarounds

| Gap | Severity | Workaround |
|---|---|---|
| No OAuth (issue #43, open since 2024) | High strategic, low immediate | App passwords behind `AuthProvider` protocol. |
| No PDS discovery at login — defaults to `bsky.social` | Medium | Surface an optional "Custom PDS" field in the login screen defaulting to `https://bsky.social`. 90% of users won't touch it. Or use [`ATResolve`](https://github.com/mattmassicotte/ATResolve) for handle→DID→service endpoint resolution before calling `authenticate`. |
| `Sendable` claims are aspirational under Swift 6 strict checking | Medium | `@preconcurrency import ATProtoKit`; `extension ATProtoKit: @unchecked @retroactive Sendable {}`. Same pattern IcySky uses. |
| 3× `Task.sleep(500_000_000)` inside `createPostRecord` | Low | ~500 ms latency on any post. Acceptable; flag in UX as "Posting…". |
| `print()` statements in `ATFacetParser` and upload paths | Low | Silence with an `OSLog` redirect in release builds if it gets noisy. |
| Force-load of thumbnail in `buildExternalEmbed` via `Data(contentsOf:)` | Low | Pre-fetch external thumbnails ourselves before calling. |
| Lexicon model regeneration could land in 0.33+ | Medium | `.upToNextMinor` pin; read release notes before bumping. |

### 8.5 Verdict

**Yellow with mitigations — proceed.** Reasons it's not green: pre-1.0,
no OAuth, manual PDS workaround needed, Sendable-overrides required.
Mitigations are above. Reasons to use it: correctly-parsed UTF-8 facet
byte offsets (kills v1's biggest bug), Keychain-backed token storage
(kills the plaintext-password bug), auto-refresh on authenticated calls,
correct PDS service-endpoint usage post-login, 2FA support, active
maintainer.

The alternative — keeping hand-rolled `BlueSkyService.swift` and fixing
it bug-by-bug — is worse. **Use ATProtoKit.**

---

## 9. Supporting libraries

### 9.1 Nuke (image loading) — pin to 13.0.6

```swift
.package(url: "https://github.com/kean/Nuke", .upToNextMinor(from: "13.0.6"))
// products: "Nuke" (core) + "NukeUI" (LazyImage). Skip NukeVideo, NukeExtensions.
```

**Canonical use (lifted from IcySky's `PostRowImagesView.swift`):**

```swift
import NukeUI

LazyImage(url: image.thumbnailImageURL) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else {
        RoundedRectangle(cornerRadius: 8).fill(.thinMaterial)
    }
}
.processors([.resize(size: CGSize(width: w, height: h))])
.frame(width: w, height: h)
.clipShape(.rect(cornerRadius: 8))
```

**App-startup pipeline config (call once from `App.init`):**

```swift
ImagePipeline.shared = ImagePipeline {
    $0.dataCache = try? DataCache(name: "app.bsky.cache")
    $0.dataCachePolicy = .automatic
    $0.imageCache = ImageCache(costLimit: 256 * 1024 * 1024, countLimit: 500)
    $0.isProgressiveDecodingEnabled = true
    $0.isUsingPrepareForDisplay = true
}
```

**Why LazyImage over Apple `AsyncImage`:** persistent memory + disk cache
(AsyncImage has neither), task coalescing (one network request shared
across duplicate cells), per-request `.resize` processors (resize at
request time so the cache key includes the size), automatic cancellation
on view disappear, prefetching, progressive JPEG.

**Bluesky CDN notes:** `cdn.bsky.app` serves WebP + JPEG with strong
`Cache-Control` + `ETag` — leave `isResumableDataEnabled = true`
(default). Use `image.thumbnailImageURL` for lists,
`image.fullSizeImageURL` for detail. WebP decodes natively on iOS 14+
without `Nuke-WebP-Plugin`.

**Gotchas:** Issue #878 — Nuke 13 crashes inside `os_unfair_lock` when
called from Swift 5 mode. We're Swift 6 mode; not affected. Set
`ImagePipeline.shared` exactly once before any view appears.

### 9.2 Pow (delight effects) — pin to 1.0.6

```swift
.package(url: "https://github.com/EmergeTools/Pow", .upToNextMajor(from: "1.0.6"))
```

License is **MIT** since EmergeTools acquisition. The Movingparts paid
tier no longer exists; the gallery at `movingparts.io/pow` redirects
installation to the EmergeTools repo.

**Curated effect list for our app:**

```swift
import Pow

// 1. Post-sent celebration
sendButton
    .changeEffect(.spray(origin: .center) {
        Image(systemName: "sparkles").foregroundStyle(.blue)
    }, value: postSentCount)

// 2. Error shake + haptic on failed login/post
loginForm
    .changeEffect(.shake(rate: .fast), value: errorCount)
    .changeEffect(.feedback(hapticNotification: .error), value: errorCount)

// 3. Template-applied / like bounce
likeButton
    .changeEffect(.jump(height: 24), value: likeCount, isEnabled: isLiked)
```

**Accessibility — wire reduce-motion at the design system layer:**

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

likeButton
    .changeEffect(.spray { heart }, value: likes, isEnabled: !reduceMotion && isLiked)
```

**Gotchas:** `.conditionalEffect(.repeat(...))` doesn't stop immediately
when the condition flips false (issue #65) — use `.changeEffect` for
state-toggle patterns. Particle effects inside a `List` cell get
clipped — wrap container with `.particleLayer(name: .feed)` and pass
`layer: .named(.feed)` to the effect. No watchOS support.

### 9.3 MarkdownUI 2.4.1 (for bios/help only — NOT post bodies)

```swift
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui",
         .upToNextMinor(from: "2.4.1"))
// product: "MarkdownUI"
```

The repo is in **maintenance mode** — gonzalezreal's new development is
in [Textual](https://github.com/gonzalezreal/textual), but Textual is
pre-1.0 (v0.3.1) with two known blockers we'd hit: issue #47 (re-parses
markdown on every render — kills composer-preview performance) and
issue #52 (`StructuredText` reports unstable intrinsic size in hosting
cells, causing overlap in `List` rows). **Do not adopt Textual until
v1.0 ships with those fixes.**

**Critical reframing:** Bluesky post text is **not** markdown — it's
plain text with `app.bsky.richtext.facet[]` arrays denoting byte ranges
that are links, mentions, hashtags. There is no `**bold**` in a
Bluesky post. So for post bodies, **don't use a markdown renderer at
all** — hand-segment facets into a `Text + Text + Text` chain. ~80 lines,
native `Text` performance, native text selection, full accessibility.

**Use MarkdownUI only where actual markdown lives:** profile bios (some
users write markdown there), in-app help, OSS attribution screens.

```swift
Markdown(profile.bio ?? "")
    .markdownTheme(
        Theme()
            .text { ForegroundColor(.primary); FontSize(15) }
            .link { ForegroundColor(.accentColor) }
    )
```

### 9.4 Keychain — native `SecItem` wrapper (no third-party dep)

The supporting-libraries research recommended KeychainAccess; the
modern-patterns research recommended the native wrapper. They converge
when you account for the App Extension story: **KeychainAccess
explicitly blocks linking into extension targets** (it sets
`-no_application_extension` linker flag), so any Share Extension or
Widget would need a hand-rolled `SecItem` wrapper anyway. Write it once.

```swift
// Sources/Logging/Keychain.swift (or wherever Keychain lives)
import Security

enum Keychain {
    enum Error: Swift.Error { case status(OSStatus) }

    static func set(_ data: Data, account: String, service: String) throws {
        let q: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:        data,
        ]
        SecItemDelete(q as CFDictionary)
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else { throw Error.status(s) }
    }

    static func data(account: String, service: String) throws -> Data? {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &item)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess else { throw Error.status(s) }
        return item as? Data
    }

    static func delete(account: String, service: String) throws {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        let s = SecItemDelete(q as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw Error.status(s) }
    }
}
```

**Accessibility rationale:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
is right for an atproto refresh token. Accessible after device unlocks
once after boot (so background refresh works); not synced to iCloud
Keychain (so the token doesn't replicate across devices); locked to
*this* device (so a restored backup forces re-login on the new device).

**Access group:** configure the entitlement up front (`$(AppIdentifierPrefix)group.com.tolb.bskytemplates`) even if we don't ship an extension at v2 launch — adding an access group later requires a Keychain migration step.

For ATProtoKit's own secrets, use its built-in `AppleSecureKeychain`. We
only reach for the native wrapper when we add OAuth (DPoP key storage)
or a Share Extension.

### 9.5 Skipped libraries

| Library | Why skipped |
|---|---|
| **KeychainAccess** | Stale (v4.2.2 from 2021), Swift 6 concurrency warnings, blocks App Extensions. Native `SecItem` wrapper is ~80 lines and we'd write it anyway for extensions. |
| **Textual** | Pre-1.0, perf issues (#47), layout issues in hosting cells (#52). Revisit at v1.0. |
| **The Composable Architecture** | Overkill for a 4-screen app. Adopt only if we grow toward IcySky / Ice Cubes complexity. |
| **MUI-clone libraries** (ComponentsKit, niceComponents, SwiftUI-Design-System-Pro) | Fight Apple's design language. Build internal `DesignSystem` module. |
| **ViewInspector** | The "no-ViewModel" approach makes view bodies trivial expressions of state. Test the state, not the body. |
| **Inject** (hot reload) | Nice-to-have, not foundational. Add later if iteration speed matters. |

---

## 10. Patterns to steal from IcySky vs to avoid

### Steal as-is
- `PostsListViewState` enum + `PostsListViewDatasource` protocol +
  reusable `PostListView` with `loadPosts(with:) -> nextState`.
- `AppState` enum carrying associated services
  (`.authenticated(client, currentUser)` / `.unauthenticated` /
  `.resuming` / `.error(Error)`).
- `Auth.configurationUpdates` `AsyncStream` as the single source of
  auth state transitions.
- Optimistic mutation: save previous state, mutate, await, revert on
  throw (their `PostContext.toggleLike()` is the template).
- Three-state `ComposerSendState` enum (`.idle` / `.loading` /
  `.error(String)`) driving a send button.
- Type-keyed environment: `.environment(client)` + `@Environment(BSkyClient.self) var client`.
- Per-screen `ErrorView(error:retry:)` with an async retry closure.

### Avoid (real anti-patterns in IcySky's source)
- **ATProtoKit symbols leaking into every UI file.** They
  `@preconcurrency import ATProtoKit` in 20+ feature files. Build a
  `BSkyClient` wrapper that's the only thing importing ATProtoKit; UI
  modules import `Bluesky` (our module), not the SDK.
- **Errors swallowed with `print()`.** Multiple call sites in
  `FeedsListView.swift`, `NotificationsListView.swift`,
  `SettingsView.swift`. Use `os.Logger` and propagate to UI via the
  state enum's `.error` case.
- **`AppTabView`'s 200 ms `DispatchQueue.main.asyncAfter` hack** for
  routing taps on the compose tab. Race-prone; do compose-tab routing
  via `.onChange(of: router.selectedTab)` with proper state, not magic
  numbers.
- **`PostContextProvider` keeps a dictionary keyed by post URI with no
  eviction.** Memory grows as you scroll. For our composer-only app this
  doesn't apply, but be aware if we ever add a feed.
- **Composer in IcySky is a stub** — all five toolbar buttons have empty
  closures, no facets, no images, no alt text. Their composer-text
  pattern-detection (`ComposerTextProcessor`) is genuinely interesting;
  the posting half is missing and we'll write it ourselves.
- **Tests are thin** — three test files, ~120 lines total. Our test
  target should be substantively better.

---

## 11. Phased plan

1. ✅ **Scaffold** — done. SPM workspace, five external deps wired, CI on `xcode` runner emitting JUnit. ATProtoKit hello-world post path proved out (retired in Phase D1).
2. ✅ **Templates port** — done (Phase A, MR !2). `@Model Template`, SwiftData CRUD UI (list / sheet-presented new / push-presented edit / swipe delete), hashtag parser. v1 UserDefaults→SwiftData migration **skipped** (no v1 users on this device).
3. ✅ **Auth** — done. `AuthProvider` protocol + `AppPasswordAuth`, ATProtoKit `AppleSecureKeychain`, login screen with closed `AuthFailureReason` mapping, `defer` + explicit `catch is CancellationError` in `restore()` (Phase D1).
4. ✅ **Compose** — done. Text-only composer (Phase B, MR !2) with 300-grapheme counter and four-state SendState machine; image attachments (Phase C, MR !3) via PhotosPicker + ImageProcessor (ImageIO-based, ≤1 MB JPEG) + per-image required alt text + aspect-ratio embed. Template picker, external link cards, and custom camera capture are shipped. Auto-facets via ATProtoKit per §8.3.
5. ✅ **Polish** — done (Phase D, MR !4). Pow send-spray + error-shake with `accessibilityReduceMotion` gates + paired haptics. `Nuke` LazyImage **deferred** until a CDN-URL surface (e.g. feed) arrives.
6. ✅ **Tests + CI** — Swift Testing throughout (139 cases across 32 suites as of Phase J2). CI uses `swift test --xunit-output` for GitLab JUnit reports plus an XcodeGen simulator build.
7. ✅ **iCloud template storage + sharing** — done (Phase J). Private CloudKit-backed SwiftData for templates, JSON import/export, UUID upsert, CloudKit entitlements, `remote-notification` background mode, and a Create Template App Intent.
8. ✅ **Camera capture** — done (Phases J1/J2). Custom `AVCaptureSession` + `AVCapturePhotoOutput` flow with Default/1:1 framing, portrait/landscape capture framing, virtual-camera zoom chips, preview/review UI, and post-capture JPEG crop.
9. ⏸ **OAuth migration** — deferred until §7.3 trigger fires.

---

## 12. Open questions

### ATProtoKit pre-1.0 churn
The maintainer warns "things will break" pre-1.0. Pin to `0.32.5` with
`.upToNextMinor`. Budget time for an API migration when bumping minors.
Lexicon model regeneration could land in 0.33+; read release notes.

### Public-client session ceiling (2 weeks)
Hard limit on OAuth refresh tokens for public clients. Even when we
migrate to OAuth, users will re-auth every 2 weeks. UX must surface this
gracefully. Confidential clients get 180 days — that'd require a
server, which we don't have. Re-evaluate if/when Bluesky offers a
different model for personal apps.

### CloudKit production setup for templates
The code path now uses private CloudKit-backed SwiftData for templates:
`TemplateStorage.makeCloudContainer()` targets
`iCloud.com.dtolb.BlueSkyTemplates`, and the app entitlement declares the
same container. XcodeGen pins automatic Apple Development signing for team
`49LQ789275` because iCloud/CloudKit entitlements cannot be signed with
Xcode's "Sign to Run Locally" identity. Real device and internal TestFlight
sync still require the Apple Developer CloudKit container, provisioning
profile, and schema deployment to be configured for the bundle ID.

### iOS minimum at later revisits
Rule: target current major minus zero for a personal app. Re-evaluate
annually around WWDC. For 2026, that's iOS 26.

### When to introduce a real DesignSystem
At v2 launch, the DesignSystem module is mostly empty (tokens + a couple
of shared modifiers). It should grow only when we see the same styling
copy-pasted 3+ times. Don't pre-build a kit.

---

## 13. One-page cheatsheet (paste into CLAUDE.md when v2 starts)

```
BlueSkyTemplates v2 — Apple-native conventions (May 2026)

Minimum target ............ iOS 26
Swift language version .... 6.2 (Approachable Concurrency, default isolation = MainActor)
Persistence ............... SwiftData + private CloudKit for templates
                            TemplateStorage owns CloudKit/local containers
Template exchange ......... Versioned JSON via TemplateExchange; upsert by UUID
App Intents ............... Narrow CreateTemplateIntent + AppShortcutsProvider
Observation ............... @Observable everywhere (no ObservableObject)
View architecture ......... No ViewModels. @Environment for services, @State for UI state.
                            Enum-typed LoadState for loading/error/loaded.
Async work ................ .task / .task(id:) — never .onAppear { Task { } }
                            async let for parallel; never MainActor.run
Service layer ............. @Observable class for state; actor for network/IO
                            All DTOs : Sendable, Hashable, Codable
Navigation ................ NavigationStack(path:) + .navigationDestination(for:)
                            One Router per tab, .sheet / .fullScreenCover for modals
                            Deep links → .onOpenURL → router.path = parse(url)
Forms ..................... @State locally; only extract to @Observable when multi-step
Bluesky SDK ............... ATProtoKit pinned to 0.32.5 (.upToNextMinor, < 0.33)
                            Only the Bluesky module imports it; UI imports our wrapper
Auth (v2) ................. AuthProvider protocol + AppPasswordAuth impl
                            ATProtoKit's AppleSecureKeychain for token storage
                            AsyncStream-driven configuration updates
Auth (eventual) ........... OAuthAuth impl via ATProtoKit OAuth (when shipped) or
                            ChimeHQ/OAuthenticator + jose-swift fallback
                            ASWebAuthenticationSession, ephemeral=true
                            DPoP keypair in Keychain (SecKey + CryptoKit)
                            client-metadata.json hosted on GitHub Pages
Keychain .................. Native SecItemAdd wrapper (~80 lines), no KeychainAccess
                            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                            Access-group entitlement configured up front
Logging ................... os.Logger with subsystem+category per module
                            print() banned (SwiftLint enforces)
                            Tokens use privacy: .private(mask: .hash)
                            OSSignposter for perf traces
Liquid Glass .............. System controls get it free. .buttonStyle(.glass) by default.
                            .glassEffect / GlassEffectContainer for custom overlays only.
Color surfaces ............ BrandColor.pageBackground for screens;
                            BrandColor.cardBackground for cards/lists.
                            LeadIcon adapts fill/glyph by color scheme.
                            No hard-coded Color.white/black UI surfaces
                            outside brand-filled contexts.
Image loading ............. Nuke 13.0.6 — LazyImage + .processors([.resize(...)])
                            Configure ImagePipeline.shared once in App.init()
                            Bluesky CDN: use thumbnailImageURL for lists
Delight effects ........... Pow 1.0.6 — .changeEffect(.spray/.shake/.jump/.feedback)
                            Always pair visual with haptic
                            Always gate with accessibilityReduceMotion
Markdown .................. MarkdownUI 2.4.1 (maintenance mode) — bios + help only
                            Post bodies: hand-segment facets into Text chains
                            Skip Textual until v1.0
Testing ................... Swift Testing (@Test / #expect) for everything new
                            Test @Observable state transitions, not view bodies
                            XCTest only for XCUIApplication UI tests
                            Skip ViewInspector
Killed in v2 .............. ObservableObject, @Published, @StateObject, @ObservedObject,
                            @EnvironmentObject, MainActor.run, UserDefaults for content,
                            JSON-in-UserDefaults, print(), KeychainAccess, ViewInspector,
                            ViewModels (the layer, not the concept), Textual (until v1.0)
```

---

## Sources

- [MasterJ93/ATProtoKit](https://github.com/MasterJ93/ATProtoKit) — Bluesky SDK
- [Dimillian/IcySky](https://github.com/Dimillian/IcySky) — reference SwiftUI client
- [Dimillian/IceCubesApp](https://github.com/Dimillian/IceCubesApp) — same author's Mastodon client
- [kean/Nuke](https://github.com/kean/Nuke) — image loading
- [EmergeTools/Pow](https://github.com/EmergeTools/Pow) — delight effects (MIT, formerly Movingparts paid)
- [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — markdown (maintenance mode)
- [gonzalezreal/textual](https://github.com/gonzalezreal/textual) — markdown successor (pre-1.0; revisit at v1.0)
- [ChimeHQ/OAuthenticator](https://github.com/ChimeHQ/OAuthenticator) — generic Swift OAuth (PAR/PKCE/DPoP scaffolding)
- [beatt83/jose-swift](https://github.com/beatt83/jose-swift) — JWT/JWS for DPoP
- [Bluesky OAuth Client docs](https://docs.bsky.app/docs/advanced-guides/oauth-client)
- [AT Protocol OAuth spec](https://atproto.com/specs/oauth)
- [Bluesky OAuth blog](https://docs.bsky.app/blog/oauth-atproto)
- [Tijs — Building OAuth for Bluesky (web/iOS)](https://tijs.leaflet.pub/3lwp4coqiws2k)
- [Tijs — OAuth for ATProto Apps Part 2: Mobile](https://tijs.leaflet.pub/3lysxh7wa4k2b)
- [Apple — ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Apple — Migrating to @Observable](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Apple — Adopting strict concurrency in Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6)
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Donny Wals — Modern logging with the OSLog framework](https://www.donnywals.com/modern-logging-with-the-oslog-framework-in-swift/)
- [Antoine van der Lee — Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
