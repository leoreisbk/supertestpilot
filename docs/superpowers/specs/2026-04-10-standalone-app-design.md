# TestPilot Standalone App Design

## Goal

Make the Mac app a self-contained download for designers and PMs while keeping the CLI fully functional for engineers — both using the same pre-built SDK artifacts instead of rebuilding from source on every run.

## Architecture

Two products, one artifact pipeline:

**Mac app** — distributes as a signed, notarized `.dmg` on GitHub releases. Downloads pre-built SDK artifacts to `~/.testpilot/` on first launch. No Gradle, no source repo, no bash script required.

**CLI** — the `testpilot` bash script stays. Removes the `build_ios_sdk.sh` call and Gradle builds from the normal usage path. Downloads pre-built artifacts to `~/.testpilot/` on first run, same cache as the Mac app.

`scripts/build_ios_sdk.sh` is demoted to a contributor-only tool — only needed when developing the TestPilot SDK itself.

## Tech Stack

- Mac app: SwiftUI, Swift concurrency, `URLSession` for artifact downloads
- Artifact hosting: GitHub releases (one release per version tag)
- iOS runner: `xcodebuild` (system tool, requires Xcode)
- Web runner: bundled fat-jar + `jlink`-generated JRE (Java 21, ~35MB)
- Android runner: standalone instrumentation APK (Phase 2)
- CI: GitHub Actions

---

## Artifact Pipeline

### What CI builds and publishes

Every git tag triggers a GitHub Actions workflow that produces:

| File | Contents | Est. size |
|---|---|---|
| `TestPilotShared.xcframework.zip` | KMM iOS XCFramework + harness project skeleton | ~20MB |
| `testpilot-web-runner.tar.gz` | fat-jar + jlink JRE (Java 21 slim modules) | ~40MB |
| `testpilot-android-runner.apk` | standalone instrumentation APK (Phase 2) | ~8MB |
| `artifacts-manifest.json` | version string + SHA256 for each artifact | <1KB |

### manifest.json format

```json
{
  "version": "1.2.0",
  "artifacts": {
    "ios": { "sha256": "abc123...", "url": "https://github.com/.../TestPilotShared.xcframework.zip" },
    "web": { "sha256": "def456...", "url": "https://github.com/.../testpilot-web-runner.tar.gz" },
    "android": { "sha256": "ghi789...", "url": "https://github.com/.../testpilot-android-runner.apk" }
  }
}
```

### Artifact cache location

All artifacts are stored in `~/.testpilot/`:

```
~/.testpilot/
  manifest.json                        ← last downloaded manifest (for staleness check)
  ios/
    TestPilotShared.xcframework/       ← extracted framework
  web/
    testpilot-web.jar                  ← fat-jar
    jre/                               ← jlink JRE
      bin/java
  android/
    testpilot-android-runner.apk       ← runner APK (Phase 2)
  harness/                             ← iOS harness project skeleton (extracted from xcframework zip)
    Harness.xcodeproj/
    AnalystTests/
      AnalystTests.swift               ← overwritten on each run
```

---

## Mac App Changes

### ArtifactManager.swift (new)

Responsible for checking and downloading artifacts. Called at app launch before any run is allowed.

Behaviour:
1. Fetch `manifest.json` from GitHub releases
2. Compare SHA256 of each artifact against what's in `~/.testpilot/`
3. Download and unpack any missing or outdated artifacts
4. If network is unavailable but artifacts already exist locally, proceed with what's cached (no hard failure)
5. If network is unavailable and no local artifacts exist, show error with instructions to connect and relaunch
6. Exposes `@Published var state: ArtifactState` (ready / downloading(progress) / failed(error))

### Platform runners (new files)

`AnalysisRunner.swift` is refactored into three focused runners:

**IOSRunner.swift**
- Extracts `TestPilotShared.xcframework` and harness skeleton to `~/.testpilot/` (done by ArtifactManager, not per-run)
- Generates `~/.testpilot/harness/AnalystTests/AnalystTests.swift` with the run's bundle ID, objective, provider, API key
- Invokes `xcodebuild test -project ~/.testpilot/harness/Harness.xcodeproj ...`
- Streams stdout, parses `TESTPILOT_STEP:` / `TESTPILOT_RESULT:` / `TESTPILOT_REPORT_PATH=` markers (unchanged protocol)
- On launch: checks `xcodebuild -version`, shows friendly setup message if Xcode is not installed

**WebRunner.swift**
- Invokes `~/.testpilot/web/jre/bin/java -jar ~/.testpilot/web/testpilot-web.jar`
- Passes config via environment variables (same as CLI today: `TESTPILOT_MODE`, `TESTPILOT_WEB_URL`, `TESTPILOT_OBJECTIVE`, etc.)
- Streams and parses stdout markers (unchanged)
- Zero system dependencies — JRE is bundled

**AndroidRunner.swift** *(Phase 2)*
- Checks `adb devices`, shows setup message if adb is not found
- Installs runner APK once: `adb install -r ~/.testpilot/android/testpilot-android-runner.apk`
- Invokes `adb shell am instrument -e ... -w co.work.testpilot.runner/androidx.test.runner.AndroidJUnitRunner`
- Streams stdout markers (unchanged)

### Settings screen

- Remove: "Script Path" field
- Add: "Check for updates" button (triggers ArtifactManager re-check)
- Provider, API key, max steps fields unchanged

### First-run UX

On first launch (or when artifacts are missing):
- Sheet appears: "Setting up TestPilot — downloading required components"
- Progress bar per artifact (iOS, Web)
- Dismisses automatically when complete
- Subsequent launches: background check only, no UI unless an update is found

---

## CLI Changes

The `testpilot` bash script changes in one place per platform:

**iOS** — replace:
```bash
scripts/build_ios_sdk.sh
xcodebuild test -project harness/Harness.xcodeproj ...
```
with:
```bash
# ensure artifact is present
_ensure_artifact ios
# use framework from cache
xcodebuild test -project ~/.testpilot/harness/Harness.xcodeproj ...
```

**Web** — replace:
```bash
./gradlew -q testpilot:jvmMainClasses
./gradlew -q testpilot:runWebRunner
```
with:
```bash
_ensure_artifact web
~/.testpilot/web/jre/bin/java -jar ~/.testpilot/web/testpilot-web.jar
```

**Android** — replace:
```bash
(cd "$SCRIPT_DIR/sdk" && ./gradlew testpilot:assembleDebug)
adb shell am instrument ... -w "$PACKAGE/..."
```
with *(Phase 2)*:
```bash
_ensure_artifact android
adb install -r ~/.testpilot/android/testpilot-android-runner.apk
adb shell am instrument ... -w co.work.testpilot.runner/...
```

**`_ensure_artifact` bash helper:**
```bash
_ensure_artifact() {
  local platform=$1
  local manifest_url="https://github.com/workco/testpilot/releases/latest/download/artifacts-manifest.json"
  # 1. curl manifest_url → parse sha256 + download url for $platform
  # 2. if local artifact exists and sha256 matches → return (nothing to do)
  # 3. if download fails and local artifact exists → warn and proceed with cached version
  # 4. if download fails and no local artifact → exit 1 with install instructions
  # 5. download artifact, verify sha256, unpack to ~/.testpilot/$platform/
}
```

`scripts/build_ios_sdk.sh` is retained as-is — used only by SDK contributors.

---

## CI / Release Pipeline

GitHub Actions workflow triggered on `git tag v*`:

```
jobs:
  build-ios:       # runs on macos-latest, builds XCFramework via Gradle
  build-web:       # runs on ubuntu-latest, builds fat-jar + jlink JRE
  build-android:   # runs on ubuntu-latest (Phase 2), builds runner APK
  publish-mac-app: # runs on macos-latest, builds + signs + notarizes .dmg
  create-release:  # uploads all artifacts + manifest.json to GitHub release
```

**Mac app signing requirements (one-time setup):**
- Apple Developer ID Application certificate → stored as CI secret
- App Store Connect API key → stored as CI secret (for `notarytool` notarization)

---

## Android Phase 2 — Standalone APK Architecture

Today the Android SDK must be embedded inside the target app's APK. The standalone approach introduces a new Gradle module:

**`sdk/testpilot-runner-android/`** — produces `testpilot-android-runner.apk`
- Depends on the existing `testpilot` Android source (AnalystAndroid, TestAnalystAndroid, etc.)
- Registers its own `AndroidJUnitRunner`
- Pre-installed on the device once via `adb install`
- UIAutomator operates at system level — controls any visible app without being embedded in it
- Arguments passed via `-e` flags as today, just with `-w co.work.testpilot.runner/...` instead of the target package

The existing `androidTarget` in `sdk/testpilot/build.gradle.kts` (which produces the AAR for embedding) is kept for teams that want to embed the SDK directly.

---

## Phasing

**Phase 1 — iOS + Web**
- CI workflow: build XCFramework + web runner
- `ArtifactManager.swift`, `IOSRunner.swift`, `WebRunner.swift`
- CLI: `_ensure_artifact` helper, iOS + Web paths updated
- Mac app Settings: remove script path field
- `.dmg` signing + notarization CI step

**Phase 2 — Android**
- New `testpilot-runner-android` Gradle module
- `AndroidRunner.swift`
- CLI: Android path updated
- CI: add Android APK build job

---

## What Does Not Change

- The SDK source (`commonMain`, `iosMain`, `androidMain`, `jvmMain`) — no changes
- The stdout marker protocol (`TESTPILOT_STEP:`, `TESTPILOT_RESULT:`, `TESTPILOT_REPORT_PATH=`)
- `scripts/build_ios_sdk.sh` — retained for SDK contributors
- The `testpilot` script interface (`analyze`/`test` subcommands, all flags)
- The harness project structure (`harness/Harness.xcodeproj`)
