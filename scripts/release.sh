#!/bin/bash
# S5: Mac App Store release pipeline (review PRO_SPEC_GAP_WORKORDER — S5).
#
# Distribution decision (recorded): Mac App Store ONLY. That means:
#   - No Developer-ID notarization/stapling step is needed (App Store builds
#     are signed for submission, not direct distribution).
#   - The pipeline is: archive (Release, signed) → export (app-store-connect)
#     → upload to App Store Connect.
#
# Credentials policy (review: "fail loud, not silently, when secrets are
# absent"): this script requires a real Apple Developer team id up front and
# refuses with a clear message otherwise. It never falls back to an unsigned
# build that would look like a success.
#
# Usage:
#   MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh                   # Mac archive + export (default)
#   MOVIECUT_TEAM_ID=XXXXXXXXXX PLATFORM=ios bash scripts/release.sh      # iOS archive + export
#   MOVIECUT_TEAM_ID=XXXXXXXXXX PLATFORM=all bash scripts/release.sh      # Mac + iOS simultaneous release
#   MOVIECUT_TEAM_ID=XXXXXXXXXX UPLOAD=1 bash scripts/release.sh          # + upload to ASC
#
# Upload requires an App Store Connect API key or an app-specific password:
#   MOVIECUT_ASC_KEY_ID / MOVIECUT_ASC_ISSUER_ID / MOVIECUT_ASC_KEY_PATH (API key)
#   — or —
#   MOVIECUT_ASC_APP_PASSWORD (app-specific password, with altool)
#
# Environment:
#   MOVIECUT_TEAM_ID     (required) Apple Developer team id (10 chars)
#   PLATFORM             (optional) "mac" (default), "ios", or "all"
#   UPLOAD               (optional) "1" to also upload to App Store Connect
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

BUILD_DIR="$REPO_DIR/build/release"
PLATFORM="${PLATFORM:-mac}"
VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml)"

fail_loud() {
  echo "RELEASE GATE FAILED: $1" >&2
  exit 1
}

# --- Preflight: credentials and platform must be valid before any build work -
case "$PLATFORM" in
  mac|ios|all) ;;
  *) fail_loud "Invalid PLATFORM='$PLATFORM' (expected 'mac', 'ios', or 'all')." ;;
esac

TEAM_ID="${MOVIECUT_TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
  fail_loud "MOVIECUT_TEAM_ID is not set.
  Get it from Xcode → Settings → Accounts (select the team → 'Team ID'),
  or from developer.apple.com → Membership Details.
  Then: MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh"
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  fail_loud "MOVIECUT_TEAM_ID '$TEAM_ID' does not look like a team id (expected 10 uppercase alphanumerics)."
fi

echo "== S5 release: MovieCut v${VERSION:-?} (platform=$PLATFORM) =="
echo "team: $TEAM_ID"

# --- Preflight: the quality gates must pass on the code being shipped -------
# The behavioral/perf gates run in nightly; for a release we re-run the fast
# local gate so an archive is never produced from code that fails build+test.
bash scripts/verify_gate.sh

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
sed "s/__TEAM_ID_PLACEHOLDER__/$TEAM_ID/" scripts/ExportOptions.plist > "$EXPORT_PLIST"

TEMP_KEYS_DIR=""
cleanup_keys() {
  if [[ -n "$TEMP_KEYS_DIR" && -d "$TEMP_KEYS_DIR" ]]; then
    rm -rf "$TEMP_KEYS_DIR"
  fi
}
trap cleanup_keys EXIT

upload_artifact() {
  local platform_type="$1"
  local artifact_path="$2"

  echo "== uploading ($platform_type) to App Store Connect =="
  if [[ -n "${MOVIECUT_ASC_KEY_ID:-}" && -n "${MOVIECUT_ASC_ISSUER_ID:-}" && -n "${MOVIECUT_ASC_KEY_PATH:-}" ]]; then
    [[ -f "$MOVIECUT_ASC_KEY_PATH" ]] || fail_loud "MOVIECUT_ASC_KEY_PATH does not exist: $MOVIECUT_ASC_KEY_PATH"
    # Stage the .p8 key under altool's expected AuthKey_<KEY_ID>.p8 filename in
    # an ephemeral 0700 directory so MOVIECUT_ASC_KEY_PATH is honored without
    # mutating the user's ~/.appstoreconnect/private_keys directory.
    if [[ -z "$TEMP_KEYS_DIR" ]]; then
      TEMP_KEYS_DIR="$(mktemp -d)"
      chmod 700 "$TEMP_KEYS_DIR"
      cp "$MOVIECUT_ASC_KEY_PATH" "$TEMP_KEYS_DIR/AuthKey_${MOVIECUT_ASC_KEY_ID}.p8"
      chmod 600 "$TEMP_KEYS_DIR/AuthKey_${MOVIECUT_ASC_KEY_ID}.p8"
    fi
    API_PRIVATE_KEYS_DIR="$TEMP_KEYS_DIR" xcrun altool --upload-app --type "$platform_type" \
      --apiKey "$MOVIECUT_ASC_KEY_ID" \
      --apiIssuer "$MOVIECUT_ASC_ISSUER_ID" \
      --file "$artifact_path"
  elif [[ -n "${MOVIECUT_ASC_APP_PASSWORD:-}" ]]; then
    xcrun altool --upload-app --type "$platform_type" \
      --username "${MOVIECUT_ASC_USERNAME:?MOVIECUT_ASC_USERNAME required with app password}" \
      --password "$MOVIECUT_ASC_APP_PASSWORD" \
      --file "$artifact_path"
  else
    fail_loud "UPLOAD=1 but no App Store Connect credentials found.
    Provide MOVIECUT_ASC_KEY_ID + MOVIECUT_ASC_ISSUER_ID + MOVIECUT_ASC_KEY_PATH
    (API key), or MOVIECUT_ASC_APP_PASSWORD + MOVIECUT_ASC_USERNAME.
    Alternatively, upload manually via Transporter:
      open -a Transporter '$artifact_path'"
  fi
  echo "uploaded ($platform_type) to App Store Connect"
}

archive_and_export_platform() {
  local target="$1"
  local scheme destination archive_path export_path artifact_glob altool_type

  if [[ "$target" == "mac" ]]; then
    scheme="MovieCutMac"
    destination="generic/platform=macOS"
    archive_path="$BUILD_DIR/MovieCut.xcarchive"
    export_path="$BUILD_DIR/export"
    artifact_glob="*.app"
    altool_type="macos"
  else
    scheme="MovieCutiOS"
    destination="generic/platform=iOS"
    archive_path="$BUILD_DIR/MovieCutiOS.xcarchive"
    export_path="$BUILD_DIR/export-ios"
    artifact_glob="*.ipa"
    altool_type="ios"
  fi

  mkdir -p "$export_path"
  echo "== archiving ($scheme, Release) =="
  xcodebuild archive \
    -project MovieCut.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$destination" \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$TEAM_ID"

  [[ -d "$archive_path" ]] || fail_loud "archive was not produced at $archive_path"

  echo "== exporting ($scheme, app-store-connect) =="
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$export_path"

  local artifact_path
  artifact_path="$(find "$export_path" -name "$artifact_glob" -maxdepth 1 | head -1)"
  [[ -n "$artifact_path" ]] || fail_loud "export did not produce ($artifact_glob) in $export_path"
  echo "exported ($target): $artifact_path"

  if [[ "${UPLOAD:-0}" == "1" ]]; then
    upload_artifact "$altool_type" "$artifact_path"
  else
    echo "To submit ($target): UPLOAD=1 with ASC credentials, or:"
    echo "  open -a Transporter '$artifact_path'"
  fi
}

if [[ "$PLATFORM" == "mac" || "$PLATFORM" == "all" ]]; then
  archive_and_export_platform "mac"
fi
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
  archive_and_export_platform "ios"
fi

echo ""
echo "S5 RELEASE PIPELINE OK (platform=$PLATFORM)"
