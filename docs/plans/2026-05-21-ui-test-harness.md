# UI test harness — XCUITest target, GitLab-runner integrated

> **Source spec:** [`docs/architecture.md`](../architecture.md) §4 ("Swift Testing for everything new. XCTest only for `XCUIApplication`. Skip ViewInspector.") and §10 ("Tests are thin — our test target should be substantively better"). Also the [UI test backlog](../ui-test-backlog.md) that drives what runs on this harness.
>
> **Goal:** stand up a native XCUITest target that drives the iOS app in the Simulator (and eventually on a device) so the kind of bug Phase E uncovered (lazy-tab-init race, only visible under real-app lifecycle) gets caught automatically on every push.
>
> **Status:** plan only. Implementation deferred — Dan wants to push feature work first. Pick this up when the backlog crosses ~10 P0/P1 items or after the next 2-3 feature phases, whichever comes first.

## Why XCUITest, not Appium / Detox / Maestro

| Option | Verdict | Why |
|---|---|---|
| **XCUITest** | ✅ Choose this | Native Apple framework. Lives in the Xcode project. Tests compile to a `.xctest` bundle alongside the app. Runs via `xcodebuild test`. Drives the app through the iOS accessibility tree — no flakey screen-coordinate clicks. Already integrates with our `xcode`-tagged GitLab runner (extend `.gitlab-ci.yml`). Emits `.xcresult`; convert to JUnit via `xcresultparser` (per the TODO already in `.gitlab-ci.yml:6-7`). Compiles against the same Swift 6.2 toolchain. No new processes, no Node, no Python, no Selenium-server. |
| **Appium** | ❌ | Adds an Appium server process, a WebDriver protocol layer, a Node-or-Python client SDK, and a wire-protocol translation. All for what becomes a thin wrapper over XCUITest anyway. Useful when you need ONE test suite across iOS + Android. We have one platform. Multi-process means more failure modes (server crash, port collision, version drift) and slower feedback loops. |
| **Detox** | ❌ | React Native focus. We're SwiftUI. No fit. |
| **Maestro** | ❌ | YAML-driven, cross-platform. Lower friction than Appium for simple flows, but uses screen-coordinate / OCR matching for some operations and gets opinionated about how flows are structured. For a personal iOS-only app already on Apple's stack, the cost (new runtime, YAML DSL) isn't worth the savings. Re-evaluate if Apple ships a non-XCUITest UI testing story. |
| **Manual Sim driving via cliclick + osascript** | 🟡 Keep for orchestrator-driven verification | Already proven (uncovered the Phase E race). Not a replacement for a real test suite — it's interactive and lives in the conversation, not in CI. Keep for orchestrator-driven flows where adding a real test would be overkill. |

**The "or better" answer:** XCUITest, because the bar for "better than Appium" on an iOS-only personal app is "doesn't add infrastructure we don't need." Native is better.

## Architecture sketch

```
App/
├── project.yml                        # XcodeGen — add UI test target here
├── BlueSkyTemplates.xcodeproj         # (gitignored, regenerated)
└── Sources/                           # the app target's @main shim
UITests/                               # NEW — UI test sources
├── Helpers/
│   ├── LaunchArguments.swift          # typed wrapper around -uiTesting et al
│   ├── Screens/                       # page-object-ish helpers per screen
│   │   ├── LoginScreen.swift
│   │   ├── TemplatesScreen.swift
│   │   ├── TemplateEditorScreen.swift
│   │   └── ComposeScreen.swift
│   └── MockAuthInjection.swift        # opt-in fake auth via launch arg
├── Phase_E_TemplateHandoff.swift      # @MainActor final class : XCTestCase
├── Auth.swift
├── Templates.swift
├── Compose.swift
└── Accessibility.swift
.gitlab-ci.yml                         # add a `ui-test` job (xcode runner)
```

### Test target via XcodeGen

Add to `App/project.yml` under `targets:`:

```yaml
BlueSkyTemplatesUITests:
  type: bundle.ui-testing
  platform: iOS
  deploymentTarget: "26.0"
  sources:
    - path: ../UITests
  dependencies:
    - target: BlueSkyTemplates       # test bundle injects into the app
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.dtolb.BlueSkyTemplatesUITests
      CODE_SIGN_IDENTITY: "-"
      SWIFT_VERSION: "6.0"
      TEST_TARGET_NAME: BlueSkyTemplates
```

And to the existing scheme's `test:` block:

```yaml
schemes:
  BlueSkyTemplates:
    test:
      config: Debug
      targets:
        - BlueSkyTemplatesUITests
```

XCUITest uses **`XCTestCase` (not Swift Testing)** by architecture §4 — Apple's `XCUIApplication` is XCTest-only.

### Launch-argument-driven fixtures

XCUITest can't reach into the app's `@Observable` services directly. Inject behavior via `XCUIApplication.launchArguments` and read them in `BlueSkyTemplatesApp.init()`. Three flags worth defining now:

```swift
// In a new file Sources/BlueSkyTemplatesApp/UITestingArgs.swift (only compiled in DEBUG):
#if DEBUG
enum UITestingArgs {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    static var useMockAuth: Bool { ProcessInfo.processInfo.arguments.contains("-mockAuth") }
    static var preSeedTemplates: [Template] { /* parse a JSON arg */ }
    static var skipKeychainRestore: Bool { ProcessInfo.processInfo.arguments.contains("-skipRestore") }
}
#endif
```

The composition root branches on these in DEBUG to inject a `MockAppPasswordAuth` (returns canned `SessionInfo` immediately) or pre-seed SwiftData with deterministic templates. **The mock injection lives inside the app target, not the test target** — XCUITest is a black-box driver and can't construct app-internal types.

### Page-object-ish screen helpers

XCUITest accessors are wordy. Wrap per-screen interactions:

```swift
// UITests/Helpers/Screens/TemplatesScreen.swift
@MainActor
struct TemplatesScreen {
    let app: XCUIApplication

    var navTitle: XCUIElement { app.navigationBars["Templates"].staticTexts["Templates"] }
    var plusButton: XCUIElement { app.navigationBars["Templates"].buttons["Add"] /* via .accessibilityLabel */ }

    func longPressRow(_ title: String) { app.cells.staticTexts[title].press(forDuration: 1.0) }
    func leadingSwipeRow(_ title: String) {
        let row = app.cells.staticTexts[title]
        row.swipeRight()
    }
    func tapUseFromContextMenu() { app.buttons["Use this template"].tap() }
}
```

This relies on **explicit `accessibilityIdentifier` / `accessibilityLabel` on production views** — most of our views ARE accessible (Labels, Buttons with text), but a few (the swipe action's "Use" button, the toolbar share icon) need `.accessibilityLabel("Use Template")` modifiers added so XCUITest can find them by name.

### CI wiring

Extend `.gitlab-ci.yml` with a new `ui-test` job, conditional on a label or branch pattern (UI tests are slower than unit tests — ~30-60s per test vs ~50ms; don't run them on every commit):

```yaml
ui-test:
  stage: test
  tags:
    - xcode
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"
  script:
    - command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
    - command -v xcresultparser >/dev/null 2>&1 || brew install xcresultparser
    - (cd App && xcodegen generate)
    - mkdir -p test-results
    - xcodebuild test
        -project App/BlueSkyTemplates.xcodeproj
        -scheme "$SCHEME"
        -destination "$DESTINATION"
        -resultBundlePath test-results/ui-test.xcresult
        -only-testing:BlueSkyTemplatesUITests
    - xcresultparser --output-format junit test-results/ui-test.xcresult > test-results/junit-ui.xml
  artifacts:
    when: always
    paths:
      - test-results/
    reports:
      junit: test-results/junit-ui.xml
    expire_in: 1 week
```

Merge with the existing `test:` job: rename current one to `unit-test:` for clarity, run both in parallel; pipeline succeeds only when both pass.

## Implementation tasks (when this lands)

Sequential — each is a fresh `swift-coder` (Opus) dispatch.

### H1 — Scaffold + smoke test

Add `UITests/` directory and the project.yml target. Land one trivial smoke test that launches the app and asserts a known view exists. Verify `xcodebuild test -only-testing:BlueSkyTemplatesUITests` exits 0.

### H2 — DEBUG-only launch arg plumbing

Add `UITestingArgs` enum, wire `BlueSkyTemplatesApp.init()` to branch on `isUITesting`, define a `MockAppPasswordAuth` conforming to `AuthProvider` that returns a canned `SessionInfo` on `session(handle:secret:)`. Tests can now skip the real login flow.

### H3 — Accessibility label sweep

Add `accessibilityIdentifier` to the handful of production views XCUITest needs by name and can't reach by visible text: `Use` swipe button (just "Use" collides with potential other buttons), Use Template toolbar (icon only), copy-URI context menu entry. Run an XCUITest accessibility audit (`XCUIElement.exists` queries) to confirm coverage.

### H4 — Page-object helpers

Land `UITests/Helpers/Screens/{Login,Templates,TemplateEditor,Compose}Screen.swift`. Each is a small struct around `XCUIApplication` exposing intent-named methods. Page objects are anti-pattern when overdone — keep these thin (1-3 lines each).

### H5 — Implement P0 backlog items

Land the three lazy-tab-init regression tests (commit `ac60d6b` is what they regress against). One file `UITests/Phase_E_TemplateHandoff.swift`.

### H6 — Implement P1 backlog items in priority order

Auth golden path, Templates CRUD, Compose send/failure. Roughly 8-12 tests across 3 files.

### H7 — CI wiring + parallelism

Add the `ui-test:` job in `.gitlab-ci.yml`. Verify it runs on MR pipelines, passes locally + remote. Decide on `-parallel-testing-enabled YES` once we have >5 tests (Xcode 26's parallel UI testing matured).

## Out of scope

- **Visual diff / screenshot testing.** XCUITest can `XCUIScreen.main.screenshot()` and we can attach screenshots to the xcresult for human review, but committing a baseline-image-diff library is its own project. Adopt only if a layout regression slips past assertion-only tests.
- **Performance / `measure` tests.** Not for our app's surface area. Architecture §1 doesn't list a perf budget; revisit if a screen feels slow.
- **iPad-specific layout.** Portrait-only on iPhone for v2 (`App/project.yml:62`). Adapt when the portrait constraint relaxes.
- **Watch / TV / visionOS.** Not targets.
- **End-to-end against the real Bluesky network.** Tests use the mock auth provider + a fake API actor that returns deterministic results. Hitting `bsky.social` from CI is flaky, slow, and risks burning the test handle's rate limit.

## Done when

1. `xcodebuild test -only-testing:BlueSkyTemplatesUITests` runs locally and on the `xcode` GitLab runner.
2. All P0 backlog items pass (the three lazy-tab-init regressions in particular).
3. CI emits a separate `junit-ui.xml` artifact distinguishable from `junit-swift-testing.xml`.
4. `docs/ui-test-backlog.md` priority column is updated to reflect what's implemented vs deferred.
5. README mentions how to run UI tests locally (`xcodebuild test ...`).

## Coordination notes

- The H2 task touches the App composition root (`BlueSkyTemplatesApp.swift`) and adds a debug-only `MockAppPasswordAuth`. Coordinate carefully — that file shouldn't grow much; the mock should live in its own file (`Sources/Auth/MockAppPasswordAuth.swift`) wrapped in `#if DEBUG`.
- `accessibilityIdentifier` is preferred over `accessibilityLabel` when adding test handles, because the label is user-facing (read by VoiceOver) and changing it for testability is a regression. Identifiers are test-only.
- iOS Simulator UI tests can be flaky if the Sim is already booted with stale state. `.gitlab-ci.yml` should call `xcrun simctl shutdown all && xcrun simctl erase all` once at the start of the `ui-test:` job (~5s overhead).
- Don't reach for `_XCUIApplication`-internal APIs. Stay in the public surface.
