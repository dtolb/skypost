# UI test backlog

> Living list of behaviors that warrant **end-to-end UI tests** in a future XCUITest target. Tracked outside `kanban.md` because it's longer-lived than a phase. When the test harness lands (see [`docs/plans/2026-05-21-ui-test-harness.md`](plans/2026-05-21-ui-test-harness.md)), implement these in priority order.
>
> Unit-tested logic (Swift Testing, `Tests/*`) is NOT relisted here — those tests already run on every push. This file only covers what XCUITest catches that unit tests can't: SwiftUI lifecycle, view-hierarchy state, real-device gestures, accessibility tree, navigation transitions.

## Priority legend

- **P0** — regression: a bug the unit-test layer let through and code review missed. Add first.
- **P1** — golden-path flows the user hits every session.
- **P2** — edge cases / accessibility / iPad-or-future-device coverage.
- **P3** — speculative / nice-to-have.

## Phase F — External link card embed

- **P1** | `URLInTextAttachesCardWithin1s` — type `Check out https://example.com today` in Compose; within ~1.5s (600ms debounce + LP fetch), expect `Link` section to appear with the card. Verifies the `.task(id: detectedURL)` + resolver chain end-to-end.
- **P1** | `URLPlusImagesSuppressesCard` — attach an image, then type a URL; expect no `Link` section appears. Verifies the `attachments.isEmpty` gate on `detectedURL`. URL still becomes a body facet (verified server-side, untestable from XCUITest — out of scope).
- **P2** | `TimeoutPathShowsRemovableFailedBanner` — point the test at a URL the mock resolver throws `.timeout` for; expect the `.failed` row with a Remove button within ~10s. Verifies the `withThrowingTaskGroup` deadline race + UI failure rendering.
- **P1** | `RemoveDuringLoadingDismissesURLAndCancelsTask` — type a URL, immediately tap Remove on the `.loading` row; expect the section disappears AND retyping the same URL does NOT re-attach (dismissedURLs sticky). Verifies the F5 fix for loading-escape + the dismissed-URL chain.
- **P1** | `TemplateApplyDoesNotAutoAttachCardForBodyURL` — create a template whose body contains `Check out https://example.com`, apply it; expect Compose body fills with that text but the Link card section depends on the post-apply debounce + auto-detect. Either it fires (current behavior) or doesn't (intended for template flow). Lock in current behavior with whichever way it shipped — this is the cross-feature regression risk the whole-phase reviewer flagged.
- **P2** | `MailtoURLDoesNotAttachCard` — type `email me at foo@bar.com`. Expect NO link card. Verifies the F5 http/https-only filter on `detectedURL` (closes F1's deferred mailto/tel characterization).
- **P3** | `LinkCardThumbnailAccessibility` — VoiceOver reads the card as one combined element ("Link preview: title. description. host") with the Remove button as a separately focusable control. Verifies the F5 a11y fix-pass.

## Phase E — Templates → Composer hand-off

- **P0** | `firstApplyAfterLaunchFillsComposer` — fresh launch, create a template, tap "Use Template" from the editor toolbar, verify Compose tab is selected AND `text` reads `body\n\n#tags`. Catches the lazy-tab-init race (commit `ac60d6b`).
- **P0** | `firstApplyViaRowContextMenuFillsComposer` — same as above but via long-press → "Use this template". Same lazy-init race.
- **P0** | `firstApplyViaLeadingSwipeFillsComposer` — same as above but via leading-swipe → "Use". Same lazy-init race.
- **P1** | `applyTwiceInARowRefillsComposer` — apply a template, edit the composer text, re-apply same template → text REPLACES (not appends), tick monotonicity verified visually.
- **P1** | `applyTemplateWithEmptyHashtagsOmitsTrailer` — template with no hashtags → composer body has no `\n\n` trailer.
- **P1** | `applyTemplateFromEditorDismissesEditorAndSwitchesTab` — verify the toolbar Use Template path: editor sheet/push dismisses, tab flips to Compose.
- **P2** | `applyUsesStoredNotUnsavedEditorState` — open template, edit `bodyText` without saving, tap Use Template; verify composer fills with the STORED `template.body`, NOT the unsaved edits. (Per the kanban-deferred UX decision; lock in current behavior until we revisit.)

## Auth (Phase A → D)

- **P1** | `badPasswordShakesFormAndShowsHaptic` — type valid handle + bogus password, tap Sign In, verify `LoginView` shakes (Pow effect under `accessibilityReduceMotion = false`). Drop the haptic check (XCUITest can't observe haptics); cover with a unit-test of the state machine instead.
- **P1** | `reduceMotionDisablesShake` — same as above with `accessibilityReduceMotion = true` (set via `XCUIApplication().launchArguments += ["-UIAccessibilityReduceMotionEnabled", "YES"]`); verify NO shake animation runs.
- **P1** | `signInSucceedsTransitionsToSignedInView` — type valid creds (against a mock auth provider — see harness plan §"Fixtures"); verify the TabView appears with Templates as default tab.
- **P1** | `coldLaunchRestoresSessionFromKeychain` — pre-seed keychain with a valid session via launch arg; verify app skips LoginView and lands on TabView.
- **P2** | `signOutFromSettingsReturnsToLogin` — from Settings tab, tap Sign Out; verify return to LoginView, keychain cleared.
- **P2** | `cancelledRestoreReturnsToSignedOut` — kill app mid-`restore()`; relaunch; verify the AuthService doesn't get stuck at `.restoring` (regression for plan #17, commit `c9c24fa`).
- **P3** | `customPDSFieldAcceptsNonDefaultURL` — if/when we surface the optional PDS field (architecture §8.4).

## Templates (Phase A)

- **P1** | `emptyStateShowsContentUnavailableView` — no templates, expect "No templates yet" + plus button.
- **P1** | `plusOpensSheetSaveAddsRow` — tap +, fill all three fields, Save; verify a row appears on the list with the right title/body/hashtags.
- **P1** | `swipeTrailingDeletesRow` — leading-swipe is Use (Phase E), trailing-swipe is Delete; verify both don't collide.
- **P1** | `tapRowPushesEditorPrefilledWithStoredValues` — tap a row, verify editor opens with stored fields populated.
- **P1** | `editAndSaveUpdatesRowAndTouchesUpdatedAt` — change body in editor, Save; verify row reflects new body and floats to top of the updatedAt-desc list (if another template exists).
- **P1** | `cancelDiscardsChanges` — open editor, type edits, Cancel; verify row unchanged.
- **P2** | `hashtagsRawWithBareCommasAndHashesParsesCorrectly` — type `#bsky, swiftui, #ios`; verify saved hashtags = `["bsky", "swiftui", "ios"]`. Unit-tested in `parseHashtags`, but the UI flow round-trip is worth verifying once.

## Compose (Phase B + C + D)

- **P1** | `submitDisabledOnEmptyText` — empty composer, Send button disabled.
- **P1** | `submitDisabledOnOverLimitText` — paste 301+ graphemes, Send disabled, counter goes negative red.
- **P1** | `submitDisabledOnAttachmentMissingAlt` — add image, leave alt blank, Send disabled.
- **P1** | `submitDisabledWhenSignedOutOrApiNil` — sentinel: if `@Environment(\.apiClient)` is nil, Send disabled; tap-and-fail produces "No account connected." banner.
- **P1** | `sendSuccessShowsSpravAndUriBanner` — wire a mock API that returns a fake URI; verify Pow spray fires (or `accessibilityReduceMotion = true` for the no-effect path) AND the URI banner appears AND auto-clears after ~2s.
- **P1** | `sendFailureShowsErrorBanner` — mock API throws; verify `.failed(message:)` banner renders.
- **P2** | `attachmentLimitFourImages` — pick 5 images; verify only 4 accepted, picker grays out.
- **P2** | `largeImageAttachmentResizesUnderOneMB` — pick a huge image; verify the attached `ComposeAttachment.jpegData.count` is under 1 MB (via accessibility label exposure or by reading the on-screen size string).
- **P2** | `removingAttachmentClearsRowAndRefocusesEditor`.
- **P2** | `copyUriFromBannerContextMenu` — long-press URI, tap Copy; verify pasteboard via `XCUIApplication.pasteboard` (where supported).

## Cross-cutting / Accessibility

- **P1** | `tabBarSwitchesPreserveState` — type a draft in Compose, switch to Settings then back; verify draft survives.
- **P2** | `darkModeRendersWithoutContrastIssues` — toggle `XCUIDevice.shared.appearance = .dark`; capture screenshots of each tab + the editor for visual review (no diff assertion yet; that's a P3 future thing).
- **P2** | `dynamicTypeAccessibilityXxxLayoutsCorrectly` — set `XCUIApplication.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]`; verify the editor + composer don't truncate or overflow.
- **P3** | `landscapeOrientationLayout` — rotate, verify nothing breaks. (Currently portrait-only on iPhone per `App/project.yml`.)

## Out of scope here

- Network correctness (covered by `BlueskyTests` unit tests + ATProtoKit's own coverage).
- Pure logic (validators, parsers, merge helpers — all in `Tests/*`).
- Visual diffing / snapshot tests — adopt only if pure XCUITest assertions can't catch a class of regression (e.g. layout shifts under Dynamic Type). Tools to evaluate at that point: `swift-snapshot-testing`, but pin a current version and only after we hit the actual problem.
