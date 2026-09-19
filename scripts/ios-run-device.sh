#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios-common.sh"

if [[ "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: bun run iphone

Build, install, and relaunch AkuMa on a paired iPhone without uninstalling it.
Connect and unlock your iPhone before running. Xcode signing must be configured.

Optional environment variables (also supported in .env.local):
  IOS_DEVICE_ID                     Select a specific iPhone by UDID
  APPLE_TEAM_ID                     Override the project's signing team
  IOS_CONFIGURATION                Debug (default) or Release
  IOS_SKIP_LAUNCH=1                 Install without launching
  IOS_ALLOW_PROVISIONING_UPDATES=0  Disable automatic provisioning updates
USAGE
    exit 0
fi
[[ $# -eq 0 ]] || ios_die "Unknown argument. Run bun run iphone --help."

detect_device_id() {
    local devices_json device_count index state device_type udid
    local candidates=() connected=()
    devices_json="$(mktemp)"
    if ! xcrun devicectl list devices --timeout 15 --json-output "$devices_json" >/dev/null; then
        rm -f "$devices_json"
        return 1
    fi
    device_count="$(plutil -extract result.devices raw -o - "$devices_json" 2>/dev/null || true)"
    if [[ ! "$device_count" =~ ^[0-9]+$ ]]; then
        rm -f "$devices_json"
        return 1
    fi
    for ((index = 0; index < device_count; index++)); do
        device_type="$(plutil -extract "result.devices.$index.hardwareProperties.deviceType" raw -o - "$devices_json" 2>/dev/null || true)"
        [[ "$device_type" == "iPhone" ]] || continue
        state="$(plutil -extract "result.devices.$index.connectionProperties.tunnelState" raw -o - "$devices_json" 2>/dev/null || true)"
        [[ "$state" == "connected" || "$state" == "disconnected" ]] || continue
        udid="$(plutil -extract "result.devices.$index.hardwareProperties.udid" raw -o - "$devices_json" 2>/dev/null || true)"
        [[ -n "$udid" ]] || continue
        candidates+=("$udid")
        if [[ "$state" == "connected" ]]; then connected+=("$udid"); fi
    done
    rm -f "$devices_json"
    if [[ ${#connected[@]} -eq 1 ]]; then
        printf '%s\n' "${connected[0]}"
    elif [[ ${#connected[@]} -eq 0 && ${#candidates[@]} -eq 1 ]]; then
        printf '%s\n' "${candidates[0]}"
    elif [[ ${#candidates[@]} -gt 1 ]]; then
        echo "Multiple iPhones found. Set IOS_DEVICE_ID to choose one (xcrun devicectl list devices)." >&2
        return 1
    else
        echo "No paired iPhone found. Connect and trust your iPhone, or set IOS_DEVICE_ID." >&2
        return 1
    fi
}

DEVICE_ID="${IOS_DEVICE_ID:-$(detect_device_id)}"
CONFIGURATION="${IOS_CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${IOS_DERIVED_DATA_PATH:-$IOS_ROOT_DIR/build/DeviceDerivedData}"
APP_PATH="${IOS_APP_PATH:-$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$IOS_SCHEME_NAME.app}"
XCODEBUILD_ARGS=(
    -project "$IOS_PROJECT_PATH"
    -scheme "$IOS_SCHEME_NAME"
    -configuration "$CONFIGURATION"
    -sdk iphoneos
    -destination "id=$DEVICE_ID"
    -derivedDataPath "$DERIVED_DATA_PATH"
)
if [[ "${IOS_ALLOW_PROVISIONING_UPDATES:-1}" != "0" ]]; then
    XCODEBUILD_ARGS+=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
fi
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    XCODEBUILD_ARGS+=("DEVELOPMENT_TEAM=$APPLE_TEAM_ID")
fi

echo "Building $IOS_SCHEME_NAME for iPhone $DEVICE_ID..."
xcodebuild "${XCODEBUILD_ARGS[@]}" build
[[ -d "$APP_PATH" ]] || ios_die "Built app not found at $APP_PATH. Set IOS_APP_PATH if the product name differs from the scheme."

echo "Installing $IOS_BUNDLE_ID_VALUE..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
if [[ "${IOS_SKIP_LAUNCH:-0}" == "1" ]]; then
    echo "Installed $IOS_BUNDLE_ID_VALUE on $DEVICE_ID."
    exit 0
fi
if ! launch_output="$(xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$IOS_BUNDLE_ID_VALUE" 2>&1)"; then
    echo "$launch_output" >&2
    echo "The app was installed. Unlock your iPhone and open AkuMa, or rerun bun run iphone." >&2
    exit 1
fi
echo "Updated and launched $IOS_BUNDLE_ID_VALUE on $DEVICE_ID."
