#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios-common.sh"
if [[ "${1:-}" == "--help" ]]; then
    echo 'Usage: bun run ios:screenshots'
    echo 'Captures input, result and guide in dedicated iPhone/iPad simulators using offline Debug fixtures.'
    echo 'Optional: IOS_SCREENSHOT_PROFILES="iphone ipad", IOS_SCREENSHOT_LANGUAGE=en, IOS_SCREENSHOT_OUTPUT_DIR, IOS_SCREENSHOT_RUNTIME'
    exit 0
fi
[[ $# -eq 0 ]] || ios_die 'Unexpected arguments; use --help.'
OUTPUT_DIR="${IOS_SCREENSHOT_OUTPUT_DIR:-$IOS_ROOT_DIR/build/app-store/screenshots}"
PROFILES="${IOS_SCREENSHOT_PROFILES:-iphone ipad}"
LANGUAGE="${IOS_SCREENSHOT_LANGUAGE:-en}"
case "$LANGUAGE" in en) LOCALE=en_US ;; ja) LOCALE=ja_JP ;; zh-Hant) LOCALE=zh_TW ;; *) ios_die 'Use en, ja, or zh-Hant for IOS_SCREENSHOT_LANGUAGE.' ;; esac
for profile in $PROFILES; do
    case "$profile" in iphone|ipad) ;; *) ios_die "Unknown screenshot profile: $profile" ;; esac
done
DERIVED_DATA="$IOS_ROOT_DIR/build/ScreenshotDerivedData"
IOS_DERIVED_DATA_PATH="$DERIVED_DATA" IOS_CONFIGURATION=Debug IOS_SDK=iphonesimulator \
    IOS_DESTINATION='generic/platform=iOS Simulator' bash "$IOS_ROOT_DIR/scripts/ios-build.sh"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$IOS_SCHEME_NAME.app"
TMP_DIR="$(mktemp -d)"
DEVICE_ID=''
cleanup() {
    if [[ -n "$DEVICE_ID" ]]; then xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true; fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT
xcrun simctl list runtimes available --json > "$TMP_DIR/runtimes.json"
RUNTIME="${IOS_SCREENSHOT_RUNTIME:-$(python3 - "$TMP_DIR/runtimes.json" <<'RUNTIME'
import json,sys
r=[x for x in json.load(open(sys.argv[1]))['runtimes'] if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
if not r: sys.exit('Install an iOS simulator runtime in Xcode.')
print(max(r,key=lambda x:tuple(map(int,x['version'].split('.'))))['identifier'])
RUNTIME
)}"
mkdir -p "$OUTPUT_DIR/$LANGUAGE"
for profile in $PROFILES; do
    case "$profile" in
        iphone) TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max; WIDTH=1320; HEIGHT=2868 ;;
        ipad) TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB; WIDTH=2064; HEIGHT=2752 ;;
    esac
    NAME="AkuMa Screenshots $profile"
    xcrun simctl list devices available --json > "$TMP_DIR/devices.json"
    DEVICE_ID="$(python3 - "$TMP_DIR/devices.json" "$RUNTIME" "$NAME" <<'DEVICE'
import json,sys
print(next((d['udid'] for d in json.load(open(sys.argv[1]))['devices'].get(sys.argv[2],[]) if d['name']==sys.argv[3]),''))
DEVICE
)"
    if [[ -z "$DEVICE_ID" ]]; then DEVICE_ID="$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME")"; fi
    xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$DEVICE_ID" -b
    xcrun simctl install "$DEVICE_ID" "$APP_PATH"
    xcrun simctl ui "$DEVICE_ID" appearance light
    xcrun simctl ui "$DEVICE_ID" content_size large
    xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
    CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$IOS_BUNDLE_ID_VALUE" data)"
    for scene in input result guide; do
        xcrun simctl terminate "$DEVICE_ID" "$IOS_BUNDLE_ID_VALUE" >/dev/null 2>&1 || true
        rm -f "$CONTAINER/Documents/screenshot-ready"
        SIMCTL_CHILD_AKUMA_SCREENSHOT_SCENE="$scene" \
            xcrun simctl launch "$DEVICE_ID" "$IOS_BUNDLE_ID_VALUE" -AppleLanguages "($LANGUAGE)" -AppleLocale "$LOCALE"
        READY=0
        for ((attempt=0; attempt<60; attempt++)); do
            if [[ -f "$CONTAINER/Documents/screenshot-ready" ]]; then READY=1; break; fi
            sleep 1
        done
        [[ "$READY" == 1 ]] || ios_die "Timed out waiting for $profile/$scene to render."
        IMAGE="$OUTPUT_DIR/$LANGUAGE/$profile-$scene.png"
        xcrun simctl io "$DEVICE_ID" screenshot --type=png --mask=ignored "$IMAGE"
        ACTUAL_WIDTH="$(sips -g pixelWidth "$IMAGE" | awk '/pixelWidth/ {print $2}')"
        ACTUAL_HEIGHT="$(sips -g pixelHeight "$IMAGE" | awk '/pixelHeight/ {print $2}')"
        [[ "$ACTUAL_WIDTH" == "$WIDTH" && "$ACTUAL_HEIGHT" == "$HEIGHT" ]] || ios_die "Unexpected dimensions: $ACTUAL_WIDTH x $ACTUAL_HEIGHT for $profile."
        echo "Captured $IMAGE"
    done
    xcrun simctl shutdown "$DEVICE_ID"
    DEVICE_ID=''
done
echo "Review the captured images in $OUTPUT_DIR/$LANGUAGE before uploading them to App Store Connect."
