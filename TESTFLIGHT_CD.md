# TestFlight CD Handoff

This file is a fresh-session handoff for the BlueSkyTemplates iOS TestFlight CD work.

## Current Repo State

- Repo: `/Users/dtolb/code/tolbnet/BlueSkyTemplates`
- Branch: `main`
- Current commit: `dd7acc8 ci: let Xcode validate TestFlight certificate pairing`
- Current tag: `v2.1.0` points at `HEAD`
- Remote: `origin/main` is up to date with local `main`

Recent relevant commits:

- `dd7acc8 ci: let Xcode validate TestFlight certificate pairing`
- `703597e docs: document runner-local App Store profile`
- `11b4183 ci: support manual TestFlight profile signing`
- `462a23b fix(ci): let archive use automatic signing`
- `e799cb6 ci: unlock shared keychain for TestFlight release`

## What Was Built

The CI/CD path now supports TestFlight upload through two signing modes:

1. Cloud-managed signing, when no local App Store profile is provided.
2. Manual export signing, when `APP_STORE_PROFILE_PATH` or `APP_STORE_PROFILE_BASE64` is set.

The intended path for this repo is the manual export path:

- Local Apple Distribution private-key identity in the runner keychain.
- Runner-local App Store provisioning profile.
- GitLab group variable `APP_STORE_PROFILE_PATH` pointing at that profile.
- `xcodebuild -exportArchive` exports with manual signing and uploads to TestFlight.

## Files Changed

- `.gitlab-ci.yml`
  - `release-testflight` unlocks `KEYCHAIN_PATH` only when `KEYCHAIN_PATH` or `KEYCHAIN_PASSWORD` is configured.
  - This preserves the cloud-signing fallback while still supporting the local CI keychain.

- `scripts/release-testflight.sh`
  - Accepts `APP_STORE_PROFILE_PATH` and `APP_STORE_PROFILE_BASE64`.
  - Validates bundle ID, profile type, and distribution signing prerequisites.
  - Installs the profile into both Xcode profile directories.
  - Uses manual export signing when an App Store profile is provided.
  - Uses profile UUID in export options to avoid stale profile-name collisions.
  - Writes `dist/release-info.txt` once export begins so failures still produce an artifact.

- `docs/RELEASE.md`
  - Documents TestFlight-only CD, dynamic version/build handling, and runner-local provisioning profile setup.

## GitLab Variables

Group: `tolbnet` (group id `52`)

Existing group variables confirmed:

- `ASC_ISSUER_ID`
- `ASC_KEY_ID`
- `ASC_KEY_PATH`
- `DEVELOPMENT_TEAM`
- `KEYCHAIN_PASSWORD`
- `KEYCHAIN_PATH`
- `NOTARY_PROFILE`

Added group variable:

- `APP_STORE_PROFILE_PATH=/Users/dtolb/.ci-signing/BlueSkyTemplates/BlueSkyTemplates_TestFlight_App_Store.mobileprovision`

Do not use `APP_STORE_PROFILE_BASE64` for the current profile. The downloaded `.mobileprovision` is 13,783 bytes and base64-encodes to 18,380 characters, which is too large for a normal GitLab variable value.

## Runner-Local Files

Provisioning profile installed on the Mac Mini runner:

```sh
/Users/dtolb/.ci-signing/BlueSkyTemplates/BlueSkyTemplates_TestFlight_App_Store.mobileprovision
```

Permissions:

```sh
chmod 700 /Users/dtolb/.ci-signing /Users/dtolb/.ci-signing/BlueSkyTemplates
chmod 600 /Users/dtolb/.ci-signing/BlueSkyTemplates/BlueSkyTemplates_TestFlight_App_Store.mobileprovision
```

The stale Store profile was moved aside here:

```sh
/Users/dtolb/Desktop/BlueSkyTemplates-stale-provisioning-profiles-20260523-142222/
```

## Signing Facts

CI keychain:

```sh
/Users/dtolb/Library/Keychains/ci.keychain-db
```

Required Apple Distribution identity:

```text
Apple Distribution: Daniel Tolbert (49LQ789275)
SHA-1: F5:D1:62:41:F7:4C:38:39:DB:9C:53:5B:CA:DA:BA:ED:70:70:EE:E7
Serial: 5F8A5D8C69067C7910DD08ABC5153524
Valid: May 23 2026 to May 23 2027
```

The new downloaded profile was verified locally:

```text
Name: BlueSkyTemplates TestFlight App Store
UUID: e5792afc-1a1d-4da3-9749-afbf59a9f018
App ID: 49LQ789275.com.dtolb.BlueSkyTemplates
Profile certificate SHA-1: F5:D1:62:41:F7:4C:38:39:DB:9C:53:5B:CA:DA:BA:ED:70:70:EE:E7
```

Useful verification commands:

```sh
security find-identity -v -p codesigning /Users/dtolb/Library/Keychains/ci.keychain-db

PROFILE=/Users/dtolb/.ci-signing/BlueSkyTemplates/BlueSkyTemplates_TestFlight_App_Store.mobileprovision
security cms -D -i "$PROFILE" > /tmp/bluesky-profile.plist
/usr/libexec/PlistBuddy -c 'Print :Name' /tmp/bluesky-profile.plist
/usr/libexec/PlistBuddy -c 'Print :UUID' /tmp/bluesky-profile.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /tmp/bluesky-profile.plist
```

## Validation Already Run

Local:

```sh
bash -n scripts/release-testflight.sh
git diff --check
glab ci lint --include-jobs
swift test
BUILD_NUMBER=1006 scripts/release-testflight.sh --unsigned-archive --skip-export 0.0.0
```

Results:

- `swift test`: passed, 139 tests.
- unsigned Release archive smoke: passed.
- GitLab CI lint: passed.

Pipeline history:

- `#395` main: passed.
- `#396` main: passed.
- `#398` main: passed.
- `#392` / `#394` tag: failed before profile setup due signing/profile issues.
- `#397` tag: failed because the script falsely rejected the profile/certificate pairing even though manual inspection showed they matched.
- `#399` tag: passed. `build`, `test`, and `release-testflight` all succeeded.

## Successful Release Pipeline

Final successful tag pipeline:

```text
Pipeline #399
Ref: v2.1.0
Commit: dd7acc8
Status: success
Jobs:
  build: success
  test: success
  release-testflight: success
```

Check it with:

```sh
glab ci list --per-page 5
glab api projects/tolbnet%2FBlueSkyTemplates/pipelines/399/jobs --paginate | jq -r '.[] | [.id,.name,.status] | @tsv'
```

Release job trace:

```sh
glab api projects/tolbnet%2FBlueSkyTemplates/jobs/1268/trace | tail -160
```

## What To Do Next

1. Confirm the build appears in App Store Connect TestFlight.

   Expected release:

   ```text
   Version: 2.1.0
   Build: 56
   Pipeline: #399
   Tag: v2.1.0
   ```

2. Keep the runner-local profile file and GitLab group variable in place.

   ```text
   APP_STORE_PROFILE_PATH=/Users/dtolb/.ci-signing/BlueSkyTemplates/BlueSkyTemplates_TestFlight_App_Store.mobileprovision
   ```

3. For future releases, create and push a semver tag from `main`.

   ```sh
   git checkout main
   git pull --ff-only origin main
   git tag -a v2.1.1 -m "Release v2.1.1"
   git push origin v2.1.1
   ```

4. Check future release pipelines with:

   ```sh
   glab ci list --per-page 5
   glab api projects/tolbnet%2FBlueSkyTemplates/pipelines/<pipeline-id>/jobs --paginate | jq -r '.[] | [.id,.name,.status] | @tsv'
   ```

5. If a future release fails, inspect the release job trace.

   ```sh
   glab api projects/tolbnet%2FBlueSkyTemplates/jobs/<release-job-id>/trace | tail -220
   ```

6. If the failure is an export/signing error:

   - Confirm `APP_STORE_PROFILE_PATH` exists on the runner.
   - Confirm the profile UUID is `e5792afc-1a1d-4da3-9749-afbf59a9f018`.
   - Confirm the profile certificate SHA-1 is `F5:D1:62:41:F7:4C:38:39:DB:9C:53:5B:CA:DA:BA:ED:70:70:EE:E7`.
   - Confirm the CI keychain contains a matching Apple Distribution private-key identity.
   - If Xcode still chooses a stale profile by name, remove or move aside stale profiles in:

     ```sh
     /Users/dtolb/Library/Developer/Xcode/UserData/Provisioning Profiles/
     /Users/dtolb/Library/MobileDevice/Provisioning Profiles/
     ```

     Do this surgically by UUID/profile name, not as a broad delete.

7. If the failure is an App Store Connect upload error:

   - The signing/export path likely worked.
   - Check the ASC API key variables:
     - `ASC_KEY_PATH`
     - `ASC_KEY_ID`
     - `ASC_ISSUER_ID`
   - Check whether App Store Connect rejected a duplicate build number.
   - Current tag pipeline build number uses `CI_PIPELINE_IID`; for `#399`, expected build number is `56`.

8. If upload reached App Store Connect but failed after creating a build, do not reuse the same build number for the same marketing version. Either:

   - create a new pipeline/tag run with a higher pipeline IID, or
   - set `BUILD_NUMBER` to a higher value for the retry.

## Important Notes

- Do not print or expose secret values from GitLab variables.
- `APP_STORE_PROFILE_PATH` is not a secret; it is just a path to a local profile on the runner.
- The `.mobileprovision` itself should stay out of the repo.
- The archive step may show a development provisioning profile before export. The intended release flow is archive first, then export re-signs for App Store/TestFlight using the manual export options.
- `v2.1.0` was force-moved during this work because earlier tag pipelines did not upload successfully. Verify App Store Connect before deciding whether to reuse or advance the version/build again.
