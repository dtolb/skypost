#!/usr/bin/env bash
#
# release-testflight.sh - archive and upload BlueSky Templates to TestFlight.
#
# Usage:
#   scripts/release-testflight.sh <version>
#   scripts/release-testflight.sh --unsigned-archive --skip-export 0.0.0
#
# Versioning:
#   <version> becomes MARKETING_VERSION / CFBundleShortVersionString.
#   BUILD_NUMBER, CI_PIPELINE_IID, or a UTC timestamp becomes
#   CURRENT_PROJECT_VERSION / CFBundleVersion.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_DIR="${REPO_ROOT}/App"
readonly PROJECT="${APP_DIR}/BlueSkyTemplates.xcodeproj"
readonly SCHEME="BlueSkyTemplates"
readonly CONFIGURATION="Release"
readonly EXPECTED_BUNDLE_ID="com.dtolb.BlueSkyTemplates"
readonly EXPORT_OPTIONS="${REPO_ROOT}/scripts/ExportOptions-TestFlight.plist"
readonly DIST_DIR="${REPO_ROOT}/dist"
readonly DEFAULT_DEVELOPMENT_TEAM="49LQ789275"
readonly MIN_XCODE_MAJOR=26

VERSION=""
BUILD_NUMBER_VALUE=""
BUILD_DIR="${BUILD_DIR:-}"
ARCHIVE_PATH=""
EXPORT_DIR=""
INFO_PATH=""
RESOLVED_DEVELOPMENT_TEAM=""
APP_STORE_PROFILE_RESOLVED_PATH=""
DISTRIBUTION_IDENTITY_SHA1=""
DRY_RUN=0
SKIP_EXPORT=0
UNSIGNED_ARCHIVE=0

log() {
    local step="$1"
    shift
    printf '[%s] %s\n' "$step" "$*"
}

die() {
    printf 'release-testflight.sh: error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/release-testflight.sh [options] <version>

Archives BlueSky Templates for iOS and uploads the build to internal
TestFlight unless --skip-export is supplied.

Arguments:
  <version>               Marketing version, e.g. 2.1.1. In CI this should
                          come from a release tag like v2.1.1.

Options:
  --dry-run               Validate inputs and print derived paths only.
  --skip-export           Archive only; do not export/upload to TestFlight.
  --unsigned-archive      Disable code signing. Requires --skip-export and is
                          intended for branch CI release smoke checks.
  -h, --help              Show this help.

Environment:
  BUILD_NUMBER            Optional numeric build number override.
  CI_PIPELINE_IID         Used as build number when BUILD_NUMBER is unset.
  DEVELOPMENT_TEAM        Apple Developer Team ID. Defaults to 49LQ789275.
  ASC_KEY_PATH            GitLab file variable path for the App Store Connect
                          .p8 key. Required for upload.
  ASC_KEY_ID              App Store Connect API key ID. Required for upload.
  ASC_ISSUER_ID           App Store Connect API issuer ID. Required for upload.
  KEYCHAIN_PATH           Optional signing keychain to unlock before upload.
  KEYCHAIN_PASSWORD       Password for KEYCHAIN_PATH.
  APP_STORE_PROFILE_PATH  Optional GitLab file variable path for an App Store
                          provisioning profile. When set, export uses manual
                          signing with this profile instead of cloud signing.
  APP_STORE_PROFILE_BASE64
                          Optional base64-encoded App Store provisioning
                          profile. Used when APP_STORE_PROFILE_PATH is unset.
  BUILD_DIR               Optional intermediates directory.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --skip-export)
                SKIP_EXPORT=1
                shift
                ;;
            --unsigned-archive)
                UNSIGNED_ARCHIVE=1
                shift
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                if [[ -n "$VERSION" ]]; then
                    die "unexpected extra argument: $1"
                fi
                VERSION="$1"
                shift
                ;;
        esac
    done

    [[ -n "$VERSION" ]] || die "<version> is required"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || die "version '${VERSION}' must look like 2.1.1"

    if [[ "$UNSIGNED_ARCHIVE" -eq 1 && "$SKIP_EXPORT" -ne 1 ]]; then
        die "--unsigned-archive requires --skip-export"
    fi

    if [[ -n "${CI_COMMIT_TAG:-}" && "${CI_COMMIT_TAG}" != "v${VERSION}" ]]; then
        die "CI_COMMIT_TAG (${CI_COMMIT_TAG}) does not match version v${VERSION}"
    fi
}

derive_build_number() {
    if [[ -n "${BUILD_NUMBER:-}" ]]; then
        BUILD_NUMBER_VALUE="$BUILD_NUMBER"
    elif [[ -n "${CI_PIPELINE_IID:-}" ]]; then
        BUILD_NUMBER_VALUE="$CI_PIPELINE_IID"
    else
        BUILD_NUMBER_VALUE="$(date -u '+%Y%m%d%H%M')"
    fi

    [[ "$BUILD_NUMBER_VALUE" =~ ^[0-9]+$ ]] \
        || die "build number '${BUILD_NUMBER_VALUE}' must be numeric"
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

require_env() {
    local name="$1"
    local desc="$2"
    if [[ -z "${!name:-}" ]]; then
        die "missing required env var ${name} (${desc})"
    fi
}

keychain_identity_source() {
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null
    else
        security find-identity -v -p codesigning 2>/dev/null
    fi
}

distribution_identity_sha1s() {
    keychain_identity_source \
        | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) "(Apple|iOS) Distribution:.*/\1/p'
}

distribution_identity_sha1() {
    distribution_identity_sha1s | head -n 1
}

has_local_distribution_identity() {
    [[ -n "$(distribution_identity_sha1)" ]]
}

has_app_store_profile_source() {
    [[ -n "${APP_STORE_PROFILE_PATH:-}" || -n "${APP_STORE_PROFILE_BASE64:-}" ]]
}

resolve_app_store_profile() {
    [[ -n "$APP_STORE_PROFILE_RESOLVED_PATH" ]] && return

    if [[ -n "${APP_STORE_PROFILE_PATH:-}" ]]; then
        [[ -f "$APP_STORE_PROFILE_PATH" ]] || die "APP_STORE_PROFILE_PATH does not point to a file"
        APP_STORE_PROFILE_RESOLVED_PATH="$APP_STORE_PROFILE_PATH"
        return
    fi

    if [[ -n "${APP_STORE_PROFILE_BASE64:-}" ]]; then
        run mkdir -p "$BUILD_DIR"
        APP_STORE_PROFILE_RESOLVED_PATH="${BUILD_DIR}/AppStore.mobileprovision"
        printf '%s' "$APP_STORE_PROFILE_BASE64" | base64 -D > "$APP_STORE_PROFILE_RESOLVED_PATH" \
            || die "APP_STORE_PROFILE_BASE64 could not be decoded"
    fi
}

unlock_signing_keychain() {
    if [[ "$UNSIGNED_ARCHIVE" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
        return
    fi

    if [[ -z "${KEYCHAIN_PATH:-}" && -z "${KEYCHAIN_PASSWORD:-}" ]]; then
        log signing "no signing keychain configured; Xcode must use login keychain or cloud signing"
        return
    fi

    require_env KEYCHAIN_PATH "path to signing keychain"
    require_env KEYCHAIN_PASSWORD "password for signing keychain"
    [[ -f "$KEYCHAIN_PATH" ]] || die "KEYCHAIN_PATH does not point to a file"

    log signing "unlocking signing keychain ${KEYCHAIN_PATH}"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-key-partition-list -S apple-tool:,apple: -s \
        -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
}

preflight() {
    log preflight "checking tools and inputs"

    require_tool xcodebuild
    require_tool xcrun
    require_tool xcodegen
    require_tool plutil

    local xcode_version_line major
    xcode_version_line="$(xcodebuild -version)"
    xcode_version_line="${xcode_version_line%%$'\n'*}"
    major="$(printf '%s\n' "$xcode_version_line" | sed -nE 's/^Xcode ([0-9]+).*/\1/p')"
    [[ -n "$major" ]] || die "could not parse Xcode version from '${xcode_version_line}'"
    if (( major < MIN_XCODE_MAJOR )); then
        die "${xcode_version_line} is too old; need Xcode ${MIN_XCODE_MAJOR}+"
    fi

    plutil -lint "$EXPORT_OPTIONS" >/dev/null

    if [[ "$UNSIGNED_ARCHIVE" -ne 1 && "$DRY_RUN" -ne 1 ]]; then
        require_env ASC_KEY_PATH "GitLab file variable containing App Store Connect .p8 key"
        require_env ASC_KEY_ID "App Store Connect API key ID"
        require_env ASC_ISSUER_ID "App Store Connect API issuer ID"
        [[ -f "$ASC_KEY_PATH" ]] || die "ASC_KEY_PATH does not point to a file"
    fi

    local default_tmp="${TMPDIR:-/tmp}"
    default_tmp="${default_tmp%/}"
    BUILD_DIR="${BUILD_DIR:-${default_tmp}/blueskytemplates-testflight-${CI_JOB_ID:-$$}}"
    ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}-${VERSION}-${BUILD_NUMBER_VALUE}.xcarchive"
    EXPORT_DIR="${BUILD_DIR}/${SCHEME}-${VERSION}-${BUILD_NUMBER_VALUE}-export"
    INFO_PATH="${DIST_DIR}/release-info.txt"
    RESOLVED_DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-$DEFAULT_DEVELOPMENT_TEAM}"

    log preflight "Xcode ${xcode_version_line#Xcode } OK"
    log preflight "version      ${VERSION}"
    log preflight "build number ${BUILD_NUMBER_VALUE}"
    log preflight "team         ${RESOLVED_DEVELOPMENT_TEAM}"
    log preflight "archive      ${ARCHIVE_PATH}"
    if [[ "$SKIP_EXPORT" -eq 1 ]]; then
        log preflight "export       skipped"
    else
        unlock_signing_keychain
        log preflight "export       TestFlight upload"
        if has_app_store_profile_source; then
            if ! has_local_distribution_identity; then
                die "APP_STORE_PROFILE_PATH/APP_STORE_PROFILE_BASE64 requires a local Apple Distribution identity"
            fi
            log signing "local Apple Distribution identity found"
            install_app_store_profile
        elif has_local_distribution_identity; then
            log signing "local Apple Distribution identity found"
        else
            log signing "no local Apple Distribution identity; Xcode must cloud-sign using App Store Connect access"
        fi
    fi
}

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

prepare() {
    log prepare "creating release directories"
    run rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
    run mkdir -p "$BUILD_DIR" "$DIST_DIR"
}

generate_project() {
    log project "generating Xcode project"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log project "would run xcodegen generate in ${APP_DIR}"
    else
        (cd "$APP_DIR" && xcodegen generate)
    fi
}

resolve_packages() {
    log resolve "resolving package dependencies"
    run xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -resolvePackageDependencies
}

archive() {
    log archive "archiving ${SCHEME} ${VERSION} (${BUILD_NUMBER_VALUE})"

    local args=(
        archive
        -project "$PROJECT"
        -scheme "$SCHEME"
        -configuration "$CONFIGURATION"
        -destination "generic/platform=iOS"
        -archivePath "$ARCHIVE_PATH"
        "MARKETING_VERSION=${VERSION}"
        "CURRENT_PROJECT_VERSION=${BUILD_NUMBER_VALUE}"
        "APS_ENVIRONMENT=production"
        "DEVELOPMENT_TEAM=${RESOLVED_DEVELOPMENT_TEAM}"
        "CODE_SIGN_STYLE=Automatic"
    )

    if [[ "$UNSIGNED_ARCHIVE" -eq 1 ]]; then
        args+=("CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=")
    else
        local asc_key_path="${ASC_KEY_PATH:-<ASC_KEY_PATH>}"
        local asc_key_id="${ASC_KEY_ID:-<ASC_KEY_ID>}"
        local asc_issuer_id="${ASC_ISSUER_ID:-<ASC_ISSUER_ID>}"
        args+=(
            -allowProvisioningUpdates
            -authenticationKeyPath "$asc_key_path"
            -authenticationKeyID "$asc_key_id"
            -authenticationKeyIssuerID "$asc_issuer_id"
        )
    fi

    run xcodebuild "${args[@]}"
}

plist_value() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :${key}" "$plist"
}

profile_plist_path() {
    local profile_path="$1"
    local plist_path="${BUILD_DIR}/$(basename "$profile_path").plist"
    security cms -D -i "$profile_path" > "$plist_path" 2>/dev/null \
        || die "could not decode provisioning profile at ${profile_path}"
    printf '%s\n' "$plist_path"
}

profile_cert_sha1s() {
    local plist_path="$1"
    local index=0

    while :; do
        local cert_xml="${BUILD_DIR}/profile-cert-${index}.xml"
        local cert_der="${BUILD_DIR}/profile-cert-${index}.der"
        if ! plutil -extract "DeveloperCertificates.${index}" xml1 -o "$cert_xml" "$plist_path" 2>/dev/null; then
            break
        fi

        awk '/<data>/{flag=1; next} /<\/data>/{flag=0} flag {gsub(/[[:space:]]/, ""); printf "%s", $0}' "$cert_xml" \
            | base64 -D > "$cert_der"
        openssl x509 -inform der -in "$cert_der" -noout -fingerprint -sha1 2>/dev/null \
            | sed -nE 's/^sha1 Fingerprint=//p' \
            | tr -d ':'

        index=$((index + 1))
    done
}

matching_profile_distribution_identity() {
    local plist_path="$1"
    local profile_cert_sha1s_value
    profile_cert_sha1s_value="$(profile_cert_sha1s "$plist_path")"

    while IFS= read -r identity_sha1; do
        [[ -n "$identity_sha1" ]] || continue
        if printf '%s\n' "$profile_cert_sha1s_value" | grep -Fxq "$identity_sha1"; then
            printf '%s\n' "$identity_sha1"
            return
        fi
    done < <(distribution_identity_sha1s)

    return 1
}

profile_has_key() {
    local plist_path="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :${key}" "$plist_path" >/dev/null 2>&1
}

install_app_store_profile() {
    if ! has_app_store_profile_source; then
        return
    fi

    [[ "$DRY_RUN" -eq 1 ]] && return
    run mkdir -p "$BUILD_DIR"
    resolve_app_store_profile

    local profile_plist profile_name profile_uuid app_identifier get_task_allow provisions_all_devices expected_app_identifier
    [[ -n "$(distribution_identity_sha1)" ]] || die "APP_STORE_PROFILE_PATH/APP_STORE_PROFILE_BASE64 requires a local Apple Distribution identity in the signing keychain"

    profile_plist="$(profile_plist_path "$APP_STORE_PROFILE_RESOLVED_PATH")"
    profile_name="$(plist_value "$profile_plist" Name)"
    profile_uuid="$(plist_value "$profile_plist" UUID)"
    app_identifier="$(plist_value "$profile_plist" Entitlements:application-identifier)"
    get_task_allow="$(plist_value "$profile_plist" Entitlements:get-task-allow)"
    provisions_all_devices="$(plist_value "$profile_plist" ProvisionsAllDevices 2>/dev/null || true)"
    expected_app_identifier="${RESOLVED_DEVELOPMENT_TEAM}.${EXPECTED_BUNDLE_ID}"

    [[ "$app_identifier" == "$expected_app_identifier" ]] \
        || die "provisioning profile app ID mismatch: expected ${expected_app_identifier}, got ${app_identifier}"
    [[ "$get_task_allow" == "false" ]] \
        || die "provisioning profile '${profile_name}' is not a distribution profile"
    ! profile_has_key "$profile_plist" ProvisionedDevices \
        || die "provisioning profile '${profile_name}' is not an App Store profile; it contains ProvisionedDevices"
    [[ "$provisions_all_devices" != "true" ]] \
        || die "provisioning profile '${profile_name}' is not an App Store profile; it provisions all devices"
    DISTRIBUTION_IDENTITY_SHA1="$(matching_profile_distribution_identity "$profile_plist")" \
        || die "provisioning profile '${profile_name}' does not include any local Apple Distribution identity"

    local mobile_profiles_dir xcode_profiles_dir
    mobile_profiles_dir="${HOME}/Library/MobileDevice/Provisioning Profiles"
    xcode_profiles_dir="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
    run mkdir -p "$mobile_profiles_dir" "$xcode_profiles_dir"
    run cp "$APP_STORE_PROFILE_RESOLVED_PATH" "${mobile_profiles_dir}/${profile_uuid}.mobileprovision"
    run cp "$APP_STORE_PROFILE_RESOLVED_PATH" "${xcode_profiles_dir}/${profile_uuid}.mobileprovision"

    log signing "installed App Store profile '${profile_name}' (${profile_uuid})"
}

validate_archive() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log validate "would inspect archived app Info.plist"
        return
    fi

    local app_info="${ARCHIVE_PATH}/Products/Applications/${SCHEME}.app/Info.plist"
    [[ -f "$app_info" ]] || die "archived app Info.plist not found at ${app_info}"

    local actual_bundle_id actual_version actual_build
    actual_bundle_id="$(plist_value "$app_info" CFBundleIdentifier)"
    actual_version="$(plist_value "$app_info" CFBundleShortVersionString)"
    actual_build="$(plist_value "$app_info" CFBundleVersion)"

    [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] \
        || die "bundle ID mismatch: expected ${EXPECTED_BUNDLE_ID}, got ${actual_bundle_id}"
    [[ "$actual_version" == "$VERSION" ]] \
        || die "version mismatch: expected ${VERSION}, got ${actual_version}"
    [[ "$actual_build" == "$BUILD_NUMBER_VALUE" ]] \
        || die "build number mismatch: expected ${BUILD_NUMBER_VALUE}, got ${actual_build}"

    log validate "archive metadata OK (${actual_bundle_id} ${actual_version} build ${actual_build})"
}

export_upload() {
    if [[ "$SKIP_EXPORT" -eq 1 ]]; then
        log export "skipping TestFlight upload"
        return
    fi

    log export "uploading archive to TestFlight"
    run mkdir -p "$EXPORT_DIR"
    local export_options="${BUILD_DIR}/ExportOptions-TestFlight.plist"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log export "would write export options with team ${RESOLVED_DEVELOPMENT_TEAM}"
    else
        cp "$EXPORT_OPTIONS" "$export_options"
        /usr/libexec/PlistBuddy -c "Set :teamID ${RESOLVED_DEVELOPMENT_TEAM}" "$export_options"
        if has_app_store_profile_source; then
            local profile_plist profile_uuid identity_sha1
            resolve_app_store_profile
            profile_plist="$(profile_plist_path "$APP_STORE_PROFILE_RESOLVED_PATH")"
            profile_uuid="$(plist_value "$profile_plist" UUID)"
            identity_sha1="${DISTRIBUTION_IDENTITY_SHA1:-$(matching_profile_distribution_identity "$profile_plist")}"
            /usr/libexec/PlistBuddy -c "Set :signingStyle manual" "$export_options"
            /usr/libexec/PlistBuddy -c "Add :signingCertificate string ${identity_sha1}" "$export_options" 2>/dev/null \
                || /usr/libexec/PlistBuddy -c "Set :signingCertificate ${identity_sha1}" "$export_options"
            /usr/libexec/PlistBuddy -c "Delete :provisioningProfiles" "$export_options" 2>/dev/null || true
            /usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "$export_options"
            /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${EXPECTED_BUNDLE_ID} string ${profile_uuid}" "$export_options"
        fi
    fi
    local asc_key_path="${ASC_KEY_PATH:-<ASC_KEY_PATH>}"
    local asc_key_id="${ASC_KEY_ID:-<ASC_KEY_ID>}"
    local asc_issuer_id="${ASC_ISSUER_ID:-<ASC_ISSUER_ID>}"
    local args=(
        xcodebuild
        -exportArchive
        -archivePath "$ARCHIVE_PATH"
        -exportPath "$EXPORT_DIR"
        -exportOptionsPlist "$export_options"
        -authenticationKeyPath "$asc_key_path"
        -authenticationKeyID "$asc_key_id"
        -authenticationKeyIssuerID "$asc_issuer_id"
    )
    if ! has_app_store_profile_source; then
        args+=(-allowProvisioningUpdates)
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        run "${args[@]}"
        return
    fi

    write_release_info pending

    set +e
    "${args[@]}"
    local status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
        cat >&2 <<'EOF'
[export] TestFlight export failed.
[export] If the log mentions "Cloud signing permission error" or no "iOS Distribution" certificate, fix one of these:
[export] - grant the App Store Connect account/API key cloud-managed distribution certificate access; or
[export] - install an Apple Distribution certificate with its private key and set APP_STORE_PROFILE_PATH or APP_STORE_PROFILE_BASE64 to a matching App Store profile.
EOF
        exit "$status"
    fi
}

write_release_info() {
    local upload_status="${1:-}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log info "would write ${INFO_PATH}"
        return
    fi

    if [[ -z "$upload_status" ]]; then
        upload_status="$([[ "$SKIP_EXPORT" -eq 1 ]] && printf 'skipped' || printf 'submitted')"
    fi

    cat > "$INFO_PATH" <<EOF
scheme=${SCHEME}
bundle_id=${EXPECTED_BUNDLE_ID}
version=${VERSION}
build_number=${BUILD_NUMBER_VALUE}
archive_path=${ARCHIVE_PATH}
export_path=${EXPORT_DIR}
testflight_upload=${upload_status}
commit=${CI_COMMIT_SHA:-unknown}
tag=${CI_COMMIT_TAG:-none}
EOF
    log info "wrote ${INFO_PATH}"
}

main() {
    parse_args "$@"
    derive_build_number
    preflight
    prepare
    generate_project
    resolve_packages
    archive
    validate_archive
    export_upload
    write_release_info
}

main "$@"
