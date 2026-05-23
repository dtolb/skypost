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

## Archive shape

The future release script should regenerate the Xcode project, archive for a
generic iOS device, and export with the TestFlight export options:

```sh
cd App
xcodegen generate
cd ..

xcodebuild archive \
  -project App/BlueSkyTemplates.xcodeproj \
  -scheme BlueSkyTemplates \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  APS_ENVIRONMENT=production \
  DEVELOPMENT_TEAM=49LQ789275 \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/ExportOptions-TestFlight.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

Use the GitLab pipeline IID or a timestamp-derived integer for
`CURRENT_PROJECT_VERSION`; App Store Connect rejects duplicate build numbers
for the same marketing version.
