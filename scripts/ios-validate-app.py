"""Validate the release contract on the actual built app, not just project settings."""
import pathlib
import plistlib
import re
import sys


def validate(app, version, build, bundle):
    app = pathlib.Path(app)
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    checks = {
        "bundle identifier": info.get("CFBundleIdentifier") == bundle,
        "marketing version": info.get("CFBundleShortVersionString") == version,
        "build number": info.get("CFBundleVersion") == build,
        "iPhone and iPad support": sorted(info.get("UIDeviceFamily", [])) == [1, 2],
        "portrait orientation": info.get("UISupportedInterfaceOrientations") == ["UIInterfaceOrientationPortrait"],
        "iPad portrait orientation": info.get("UISupportedInterfaceOrientations~ipad", info.get("UISupportedInterfaceOrientations")) == ["UIInterfaceOrientationPortrait"],
        "full-screen iPad compatibility": info.get("UIRequiresFullScreen") is True,
    }
    with (app / "PrivacyInfo.xcprivacy").open("rb") as f:
        privacy = plistlib.load(f)
    checks["UserDefaults reason"] = any(
        item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
        and "CA92.1" in item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in privacy.get("NSPrivacyAccessedAPITypes", [])
    )
    failures = [name for name, passed in checks.items() if not passed]
    if failures:
        raise ValueError("Invalid app: " + ", ".join(failures))


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        if len(arguments) == 1:
            project = pathlib.Path(__file__).resolve().parents[1] / "apps/ios/Akuma.xcodeproj/project.pbxproj"
            settings = project.read_text()
            def setting(key):
                return re.search(r"\b" + key + r" = ([^;]+);", settings).group(1).strip('"')
            arguments += [setting("MARKETING_VERSION"), setting("CURRENT_PROJECT_VERSION"), setting("PRODUCT_BUNDLE_IDENTIFIER")]
        validate(*arguments)
    except (OSError, ValueError, TypeError) as error:
        sys.exit(str(error))
    print("Built app version, device families, portrait settings and privacy manifest verified.")
