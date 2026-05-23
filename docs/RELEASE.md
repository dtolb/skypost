# TestFlight release notes

This app is distributed only through internal TestFlight for the foreseeable
future. The release path should stay iOS-native: archive with Xcode, export
with App Store Connect signing, and upload to TestFlight. Do not copy the
macOS Developer ID / notarization / DMG flow from `dans-extra-snap`.

## Current release gaps covered

- `CFBundleShortVersionString` and `CFBundleVersion` now come from
  `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, so a release script can
  inject a monotonically increasing TestFlight build number without editing
  plist files.
- `aps-environment` now comes from `APS_ENVIRONMENT`. Development builds keep
  `development`; TestFlight archives must pass `APS_ENVIRONMENT=production`.
- `scripts/ExportOptions-TestFlight.plist` targets App Store Connect upload,
  automatic signing, the Production CloudKit environment, debug-symbol upload,
  and internal TestFlight only.
- `.gitignore` excludes local IPA/archive outputs and App Store Connect
  signing material.

## One-time Apple setup

Before a tag-driven upload job can be reliable:

- App Store Connect app record exists for `com.dtolb.BlueSkyTemplates`.
- The private CloudKit container `iCloud.com.dtolb.BlueSkyTemplates` exists,
  its schema has been deployed to Production, and the bundle ID has the iCloud
  and push capabilities enabled.
- A CI-capable App Store Connect API key exists. The future release job should
  receive it as masked/file GitLab CI variables and invoke `xcodebuild` with
  `-allowProvisioningUpdates`, `-authenticationKeyPath`,
  `-authenticationKeyID`, and `-authenticationKeyIssuerID`.
- Distribution signing is available to the runner. The preferred path is
  cloud-managed distribution signing with the App Store Connect account/key
  allowed to use cloud-managed distribution certificates. The fallback is a
  local Apple Distribution certificate, including its private key, installed in
  the runner keychain.

## Versioning

Release tags are the source of truth for the user-facing version:

- Tag `v2.1.1` uploads `MARKETING_VERSION=2.1.1`.
- `BUILD_NUMBER` can override the build number.
- In GitLab CI, `CI_PIPELINE_IID` becomes `CURRENT_PROJECT_VERSION`.
- Outside CI, the script falls back to a UTC timestamp build number.

App Store Connect rejects duplicate build numbers for the same marketing
version, so rerun a failed upload with `BUILD_NUMBER=<new number>` if the
previous attempt already reached App Store Connect.

## CI jobs

- Branch and merge-request pipelines run `release-check`, which performs an
  unsigned Release archive and skips export/upload. This exercises the same
  version/build injection and generic iOS archive path without needing Apple
  credentials.
- Tags matching `vX.Y.Z` run `release-testflight`, which signs, archives, and
  uploads to internal TestFlight with App Store Connect API credentials.
- The release script does not pass a global `CODE_SIGN_IDENTITY` override.
  Forcing `Apple Distribution` globally at archive time conflicts with
  automatically signed package resource bundles.
- Debug builds explicitly use `Apple Development`; Release builds explicitly
  use `Apple Distribution` for the app target so archive/export entitlements
  line up with TestFlight expectations.
- Release intermediates are written to a per-job temp directory by default.
  Set `BUILD_DIR` only when intentionally keeping an archive for local
  inspection.

## Signing failures

If the tag job archives successfully and then fails during export with
`Cloud signing permission error` or `No signing certificate "iOS Distribution"
found`, the GitLab variables are reaching Xcode but the runner cannot complete
distribution signing.

Fix one of these two paths:

- Grant the App Store Connect account/API key access to cloud-managed
  distribution certificates.
- Install an active Apple Distribution certificate with its private key on the
  runner before the release job runs.

## Archive shape

The release script regenerates the Xcode project, archives for a generic iOS
device, and exports with the TestFlight export options:

```sh
scripts/release-testflight.sh 2.1.1
```

For local release-path validation without signing:

```sh
BUILD_NUMBER=1 scripts/release-testflight.sh --unsigned-archive --skip-export 0.0.0
```
