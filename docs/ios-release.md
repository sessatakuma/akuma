# iOS release workflow

AkuMa ships for iPhone and iPad in portrait. The workflow adapts OnTrack's local
Xcode archive/export/upload commands. It does not submit a version to App Review.

## Setup

Use a Mac with Xcode, an iOS SDK, Python 3, and Bun. Sign in to Xcode with a
team enrolled in the Apple Developer Program and register the bundle identifier
`dev.sessatakuma.akuma`. Create the matching app record in App Store Connect.
Existing account setup must be verified in Apple; the scripts cannot infer it.

Copy the relevant settings from `.env.ios.example` into `.env.local`. Bun loads
that file when running package scripts. When invoking a shell script directly,
export the variables instead. Keep signing keys outside the repository.

- `APPLE_TEAM_ID`: the signing team, required for distribution commands.
- `IOS_MARKETING_VERSION`: defaults to the version in the Xcode project.
- `IOS_BUILD_NUMBER`: required integer, 1–9999. Choose an unused number greater
  than the latest App Store Connect upload. The scripts never silently bump it.
- `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`: optional API credentials; set all
  three together. Otherwise Xcode uses its configured account.
- `IOS_ALLOW_PROVISIONING_UPDATES=0`: opt out of automatic provisioning updates.

## Commands

| Command                     | Effect                                                              |
| --------------------------- | ------------------------------------------------------------------- |
| `bun run iphone`            | Build, install over the existing app, and launch on a paired iPhone |
| `bun run ios`               | Build, install, and launch in Simulator                             |
| `bun run ios:check`         | Validate the project and parse Swift                                |
| `bun run ios:test`          | Run session/model regression tests                                  |
| `bun run ios:pipeline:test` | Run distribution script tests with mocked Xcode; no upload          |
| `bun run ios:release:check` | Validate version/signing configuration locally; no build or upload  |
| `bun run ios:archive`       | Create a signed Release archive and source/version record           |
| `bun run ios:export`        | Export that archive as a local App Store Connect IPA                |
| `bun run ios:upload`        | Upload that archive and its symbols to App Store Connect            |
| `bun run ios:release`       | Run checks/tests, archive, then upload                              |
| `bun run ios:screenshots`   | Capture deterministic iPhone and iPad store screenshots             |

For example, after confirming the next build number in App Store Connect:

```bash
IOS_MARKETING_VERSION=0.1.0 IOS_BUILD_NUMBER=2 bun run ios:release:check
IOS_MARKETING_VERSION=0.1.0 IOS_BUILD_NUMBER=2 bun run ios:release
```

Artifacts live in `build/releases/<version>-<build>/`: the `.xcarchive` (including
dSYMs), `release.json` (commit, dirty-worktree status, version, build, Xcode), and
export/upload output. Preserve this folder with the release's source revision.
Set `IOS_RELEASE_DIR` to change its location.

An existing archive is never overwritten. Retry an interrupted upload with
`ios:upload` and the same version/build. A source change needs a new build number
and archive. Build number management is disabled during export so the tested
archive and uploaded version retain the same identity. Separate machines must
coordinate build numbers through App Store Connect.

The archive validator checks the packaged bundle identifier, version, build,
iPhone/iPad support, portrait settings, and UserDefaults privacy declaration.
Release builds always use the production API and exclude screenshot fixtures.

## Screenshots

Run `bun run ios:screenshots`. It builds Debug once and captures input, result,
and guide scenes in dedicated `AkuMa Screenshots` simulators. Fixtures are local,
do not call the API, and keep session data separate from ordinary app sessions.
The script waits for the scene's readiness marker, checks pixel dimensions, and
shuts down each dedicated simulator after capture.

Outputs: `build/app-store/screenshots/en/`. Review every image before upload.
The default profiles are 6.9-inch iPhone (1320×2868) and 13-inch iPad (2064×2752).
Install the iPhone 17 Pro Max and iPad Pro 13-inch M5 simulator device types and
an iOS runtime in Xcode. The newest installed available iOS runtime is selected;
set `IOS_SCREENSHOT_RUNTIME` to pin a runtime identifier.

```bash
IOS_SCREENSHOT_LANGUAGE=ja bun run ios:screenshots
IOS_SCREENSHOT_LANGUAGE=zh-Hant bun run ios:screenshots
IOS_SCREENSHOT_PROFILES=iphone bun run ios:screenshots
```

`IOS_SCREENSHOT_OUTPUT_DIR` can select a different output directory. These are
real app captures, not composited marketing cards. Reusing the dedicated
simulators resets their screenshot session; use ordinary simulators for your own
work. iPad is included because the shipping app supports it even in portrait.

## CI

`.github/workflows/ios.yml` runs on PRs to main, pushes to main, and manual
requests. A macOS runner runs pipeline tests, session tests, project checks, a
Debug simulator build, and an unsigned Release device build with bundle
validation. It needs no Apple credentials and never uploads a build.

Make `Build and test iOS` a required branch-protection check in GitHub after its
first successful run. Repository workflow files do not configure that setting.

## TestFlight and App Review handoff

1. Confirm the archive's commit and `release.json`; ship from a clean checkout.
2. Upload, then wait for Apple processing. Resolve signing/validation notices.
3. Complete the build's export-compliance answers based on the app's actual use;
   the repository does not pre-answer the legal questionnaire.
4. Add the processed build to your internal TestFlight group. For external
   testers, complete the beta details and Apple's review steps as applicable.
5. Test fresh install and update over an existing version, draft/correction
   preservation, failed requests, cancellation, Dynamic Type, VoiceOver,
   sharing, word editing, and portrait behavior on iPhone and iPad.
6. Finalize the listing, screenshots, support URL, privacy policy, App Privacy
   answers, age rating, review contact, and availability. Materials are in
   `docs/app-store/`; privacy content remains a draft until operator details and
   server/upstream retention are confirmed.
7. Select the exact TestFlight-tested build for the App Store version, enter
   release notes, and submit for review in App Store Connect.
8. Choose manual release or the desired rollout setting explicitly in App Store
   Connect. Retain the archive/dSYMs and monitor TestFlight/App Store crash reports.

Uploading is not publication. App Review submission and release are separate
App Store Connect actions. No script changes agreements, pricing, tester groups,
review status, or release availability.

References: [Apple upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app),
[required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
