#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios-common.sh"
ACTION="${1:-release}"
if [[ "$ACTION" == "--help" ]]; then
    cat <<'USAGE'
Usage: bun run ios:release[:check]
       bun run ios:archive | ios:export | ios:upload

Set APPLE_TEAM_ID, IOS_MARKETING_VERSION (optional; defaults to the project),
and IOS_BUILD_NUMBER (required positive integer, greater than previous uploads).
Optional ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID must be supplied together.
Bun loads .env.local; direct bash invocations use exported environment variables.

check: validate local configuration only (no signing, build, or upload).
archive: create a signed Release archive and source/version record.
export: export that archive to a local IPA.
upload: upload that archive to App Store Connect, including symbols.
release: run checks/tests, archive, and upload. Does not submit to App Review.

Artifacts: build/releases/<version>-<build>/
Override IOS_RELEASE_DIR for a different artifact directory.
USAGE
    exit 0
fi
[[ $# -le 1 ]] || ios_die "Unexpected arguments; use --help."
case "$ACTION" in check|archive|export|upload|release) ;; *) ios_die "Unknown release action: $ACTION" ;; esac

VERSION="${IOS_MARKETING_VERSION:-$(awk -F= '/^[[:space:]]*MARKETING_VERSION =/ {gsub(/[;[:space:]]/, "", $2); print $2; exit}' "$IOS_PROJECT_PATH/project.pbxproj")}"
BUILD_NUMBER="${IOS_BUILD_NUMBER:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ios_die "IOS_MARKETING_VERSION must use major.minor.patch."
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,3}$ ]] || ios_die "Set IOS_BUILD_NUMBER to an unused integer from 1 to 9999 (check App Store Connect)."
[[ "${APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || ios_die "Set APPLE_TEAM_ID to your 10-character signing team ID."
AUTH_ARGS=()
if [[ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]]; then
    [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || ios_die "Set ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID together."
    [[ -r "$ASC_KEY_PATH" ]] || ios_die "ASC_KEY_PATH is not readable."
    AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
PROVISIONING_ARGS=()
if [[ "${IOS_ALLOW_PROVISIONING_UPDATES:-1}" != "0" ]]; then PROVISIONING_ARGS=(-allowProvisioningUpdates); fi
RELEASE_DIR="${IOS_RELEASE_DIR:-$IOS_ROOT_DIR/build/releases/$VERSION-$BUILD_NUMBER}"
ARCHIVE_PATH="$RELEASE_DIR/$IOS_SCHEME_NAME.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$IOS_SCHEME_NAME.app"

if [[ "$ACTION" == "check" ]]; then
    plutil -lint "$IOS_APP_DIR/PrivacyInfo.xcprivacy" >/dev/null
    echo "Release configuration is valid: $VERSION ($BUILD_NUMBER). Signing access and the unused build number must be verified with Apple."
    exit 0
fi

if [[ "$ACTION" == "release" ]]; then
    bash "$IOS_ROOT_DIR/scripts/ios-check.sh"
    bash "$IOS_ROOT_DIR/scripts/ios-test.sh"
    python3 "$IOS_ROOT_DIR/tests/ios/release_pipeline_test.py"
fi
if [[ "$ACTION" == "archive" || "$ACTION" == "release" ]]; then
    [[ ! -e "$ARCHIVE_PATH" ]] || ios_die "Archive already exists at $ARCHIVE_PATH. Use ios:export/ios:upload to reuse it, or choose a new build number."
    mkdir -p "$RELEASE_DIR"
    xcodebuild archive -project "$IOS_PROJECT_PATH" -scheme "$IOS_SCHEME_NAME" \
        -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" \
        ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
        "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" "MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS='
    python3 "$IOS_ROOT_DIR/scripts/ios-validate-app.py" "$APP_PATH" "$VERSION" "$BUILD_NUMBER" "$IOS_BUNDLE_ID_VALUE"
    python3 - "$IOS_ROOT_DIR" "$RELEASE_DIR" "$VERSION" "$BUILD_NUMBER" <<'RECORD'
import json, pathlib, subprocess, sys
root, output, version, build = sys.argv[1:]
def git(*args): return subprocess.check_output(['git', '-C', root, *args], text=True).strip()
record = {'version': version, 'build': build, 'commit': git('rev-parse','HEAD'), 'workingTreeDirty': bool(git('status','--porcelain')), 'xcode': subprocess.check_output(['xcodebuild','-version'],text=True).strip()}
pathlib.Path(output, 'release.json').write_text(json.dumps(record,indent=2)+'\n')
RECORD
    echo "Archive and release record: $RELEASE_DIR"
    [[ "$ACTION" != "archive" ]] || exit 0
fi

[[ -d "$ARCHIVE_PATH" ]] || ios_die "Archive missing. Run bun run ios:archive with the same version and build number."
python3 "$IOS_ROOT_DIR/scripts/ios-validate-app.py" "$APP_PATH" "$VERSION" "$BUILD_NUMBER" "$IOS_BUNDLE_ID_VALUE"
DESTINATION=export
[[ "$ACTION" == "export" ]] || DESTINATION=upload
OPTIONS_DIR="$(mktemp -d)"
trap 'rm -rf "$OPTIONS_DIR"' EXIT
python3 - "$OPTIONS_DIR/ExportOptions.plist" "$DESTINATION" "$APPLE_TEAM_ID" <<'OPTIONS'
import plistlib, sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump({'method':'app-store-connect','destination':sys.argv[2],'teamID':sys.argv[3], 'signingStyle':'automatic','stripSwiftSymbols':True,'uploadSymbols':True,'manageAppVersionAndBuildNumber':False},f)
OPTIONS
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$RELEASE_DIR/$DESTINATION" \
    -exportOptionsPlist "$OPTIONS_DIR/ExportOptions.plist" \
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}
echo "Completed $DESTINATION for $VERSION ($BUILD_NUMBER). Archive and dSYMs remain in $RELEASE_DIR."
if [[ "$DESTINATION" == "upload" ]]; then
    echo "Next: wait for App Store Connect processing, test in TestFlight, then select this build for App Review."
fi
