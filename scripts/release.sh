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
#   MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh          # archive + export
#   MOVIECUT_TEAM_ID=XXXXXXXXXX UPLOAD=1 bash scripts/release.sh # + upload to ASC
#
# Upload requires an App Store Connect API key or an app-specific password:
#   MOVIECUT_ASC_KEY_ID / MOVIECUT_ASC_ISSUER_ID / MOVIECUT_ASC_KEY_PATH (API key)
#   — or —
#   MOVIECUT_ASC_APP_PASSWORD (app-specific password, with altool)
#
# Environment:
#   MOVIECUT_TEAM_ID     (required) Apple Developer team id (10 chars)
#   UPLOAD               (optional) "1" to also upload to App Store Connect
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

BUILD_DIR="$REPO_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/MovieCut.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
SCHEME="MovieCutMac"
VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml)"

fail_loud() {
  echo "RELEASE GATE FAILED: $1" >&2
  exit 1
}

# --- Preflight: credentials must exist before any build work ----------------
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

echo "== S5 release: MovieCut v${VERSION:-?} (Mac App Store) =="
echo "team: $TEAM_ID"

# --- Preflight: the quality gates must pass on the code being shipped -------
# The behavioral/perf gates run in nightly; for a release we re-run the fast
# local gate so an archive is never produced from code that fails build+test.
bash scripts/verify_gate.sh

# --- 1) Archive (Release, signed with the team) ------------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
echo "== archiving ($SCHEME, Release) =="
xcodebuild archive \
  -project MovieCut.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID"

[[ -d "$ARCHIVE_PATH" ]] || fail_loud "archive was not produced at $ARCHIVE_PATH"

# --- 2) Export (app-store-connect method) -------------------------------------
echo "== exporting (app-store-connect) =="
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
sed "s/__TEAM_ID_PLACEHOLDER__/$TEAM_ID/" scripts/ExportOptions.plist > "$EXPORT_PLIST"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH"

APP_PATH="$(find "$EXPORT_PATH" -name '*.app' -maxdepth 1 | head -1)"
[[ -n "$APP_PATH" ]] || fail_loud "export did not produce an .app in $EXPORT_PATH"
echo "exported: $APP_PATH"

# --- 3) (Optional) Upload to App Store Connect --------------------------------
if [[ "${UPLOAD:-0}" == "1" ]]; then
  echo "== uploading to App Store Connect =="
  if [[ -n "${MOVIECUT_ASC_KEY_ID:-}" && -n "${MOVIECUT_ASC_ISSUER_ID:-}" && -n "${MOVIECUT_ASC_KEY_PATH:-}" ]]; then
    xcrun altool --upload-app --type macos \
      --apiKey "$MOVIECUT_ASC_KEY_ID" \
      --apiIssuer "$MOVIECUT_ASC_ISSUER_ID" \
      --file "$APP_PATH"
  elif [[ -n "${MOVIECUT_ASC_APP_PASSWORD:-}" ]]; then
    xcrun altool --upload-app --type macos \
      --username "${MOVIECUT_ASC_USERNAME:?MOVIECUT_ASC_USERNAME required with app password}" \
      --password "$MOVIECUT_ASC_APP_PASSWORD" \
      --file "$APP_PATH"
  else
    fail_loud "UPLOAD=1 but no App Store Connect credentials found.
    Provide MOVIECUT_ASC_KEY_ID + MOVIECUT_ASC_ISSUER_ID + MOVIECUT_ASC_KEY_PATH
    (API key), or MOVIECUT_ASC_APP_PASSWORD + MOVIECUT_ASC_USERNAME.
    Alternatively, upload the .app manually via Transporter:
      open -a Transporter '$APP_PATH'"
  fi
  echo "uploaded to App Store Connect"
else
  echo ""
  echo "== export complete =="
  echo "To submit: UPLOAD=1 with ASC credentials, or:"
  echo "  open -a Transporter '$APP_PATH'"
fi

echo ""
echo "S5 RELEASE PIPELINE OK"
echo "  archive: $ARCHIVE_PATH"
echo "  app:     $APP_PATH"
