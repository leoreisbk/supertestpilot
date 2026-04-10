# Standalone App — Phase 1 (iOS + Web) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Mac app a self-contained download and eliminate Gradle/build-script dependencies from the normal CLI flow for iOS and Web.

**Architecture:** Pre-built SDK artifacts (XCFramework + web fat-jar + jlink JRE) are published to GitHub releases. Both the Mac app (via ArtifactManager.swift) and the CLI (via `_ensure_artifact` bash helper) download them once to `~/.testpilot/`. The Mac app loses its bash script path dependency entirely; three new Swift files (ArtifactManager, IOSRunner, WebRunner) replace AnalysisRunner's script-shelling logic.

**Tech Stack:** Swift 5.9, SwiftUI, Observation framework, URLSession, CryptoKit, Kotlin Multiplatform (unchanged), Gradle Shadow plugin, jlink (Java 21), GitHub Actions

---

## File Map

| File | Change |
|---|---|
| `mac-app/TestPilotApp/Services/ArtifactManager.swift` | **Create** — download/update artifacts from GitHub releases |
| `mac-app/TestPilotApp/Services/IOSRunner.swift` | **Create** — bundle ID resolution, test file generation, xcodebuild Process |
| `mac-app/TestPilotApp/Services/WebRunner.swift` | **Create** — java -jar Process with env vars |
| `mac-app/TestPilotApp/Services/AnalysisRunner.swift` | **Modify** — remove script path, delegate to runners, fix marker parsing |
| `mac-app/TestPilotApp/Services/SettingsStore.swift` | **Modify** — remove scriptPath, discoverScriptPath() |
| `mac-app/TestPilotApp/Views/SettingsView.swift` | **Modify** — remove Script section |
| `mac-app/TestPilotApp/Views/ContentView.swift` | **Modify** — add ArtifactManager, setup sheet |
| `harness/Harness.xcodeproj/project.pbxproj` | **Modify** — framework path → `$(HOME)/.testpilot/ios/` |
| `scripts/build_ios_sdk.sh` | **Modify** — copy framework + harness to `~/.testpilot/` after build |
| `sdk/testpilot/build.gradle.kts` | **Modify** — add Shadow plugin + shadowJar task |
| `testpilot` | **Modify** — add `_ensure_artifact`, update iOS/web/web-login sections |
| `.github/workflows/release.yml` | **Create** — build + publish artifacts + DMG |

---

### Task 1: Shadow plugin for fat-jar

**Files:**
- Modify: `sdk/testpilot/build.gradle.kts`

The web runner today requires Gradle's full classpath resolution (`./gradlew runWebRunner`). A fat-jar bundles everything into one file that `java -jar` can run directly.

- [ ] **Step 1: Add Shadow plugin to build.gradle.kts**

Open `sdk/testpilot/build.gradle.kts` and replace the plugins block and add the shadowJar task:

```kotlin
plugins {
    id("org.jetbrains.kotlin.multiplatform")
    kotlin("plugin.serialization") version "2.1.20"
    id("com.android.library")
    id("com.github.johnrengelman.shadow") version "8.1.1"
}
```

At the end of the file, after the existing tasks, add:

```kotlin
// ── Web fat-jar ───────────────────────────────────────────────────────────────

tasks.register<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    group = "build"
    description = "Produces a self-contained fat-jar for the web runner"
    archiveBaseName.set("testpilot-web")
    archiveClassifier.set("")
    archiveVersion.set("")
    from(kotlin.jvm().compilations["main"].output.allOutputs)
    configurations = listOf(
        kotlin.jvm().compilations["main"].runtimeDependencyFiles as Configuration
    )
    manifest {
        attributes["Main-Class"] = "co.work.testpilot.MainKt"
    }
    dependsOn("jvmMainClasses")
    mergeServiceFiles()
    // Playwright bundles its own driver — exclude duplicate signatures
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
}
```

- [ ] **Step 2: Add Shadow plugin to sdk/settings.gradle.kts or sdk/build.gradle.kts plugin management**

Check if `sdk/settings.gradle.kts` exists:

```bash
ls /Users/leonardo.reis/Projects/WorkCo/testpilot/sdk/settings.gradle.kts
```

If it exists, check if it has a `pluginManagement` block. If not, the plugin resolves from Gradle Plugin Portal automatically (which it does for Shadow 8.x). No change needed.

- [ ] **Step 3: Build the fat-jar to verify**

```bash
cd /Users/leonardo.reis/Projects/WorkCo/testpilot
scripts/build_ios_sdk.sh  # ensure .def files exist first (needed for KMP compilation)
cd sdk && ./gradlew testpilot:shadowJar
```

Expected: `sdk/testpilot/build/libs/testpilot-web.jar` created (~50-80MB).

- [ ] **Step 4: Smoke-test the fat-jar**

```bash
TESTPILOT_MODE=test \
TESTPILOT_WEB_URL=https://example.com \
TESTPILOT_OBJECTIVE="page loads" \
TESTPILOT_API_KEY=dummy \
TESTPILOT_PROVIDER=openai \
TESTPILOT_MAX_STEPS=1 \
TESTPILOT_OUTPUT=/tmp/test.html \
java -jar sdk/testpilot/build/libs/testpilot-web.jar
```

Expected: starts (may fail with API error, but should not throw `ClassNotFoundException` or `NoClassDefFoundError`).

- [ ] **Step 5: Commit**

```bash
git add sdk/testpilot/build.gradle.kts
git commit -m "build(web): add Shadow plugin for standalone fat-jar"
```

---

### Task 2: Harness xcodeproj + build script update

**Files:**
- Modify: `harness/Harness.xcodeproj/project.pbxproj`
- Modify: `scripts/build_ios_sdk.sh`

The harness xcodeproj currently references the framework at a repo-relative path. Change it to `$(HOME)/.testpilot/ios/` so it works from any location. Update `build_ios_sdk.sh` to deploy artifacts to that location after building.

- [ ] **Step 1: Update framework path in project.pbxproj**

In `harness/Harness.xcodeproj/project.pbxproj`, find line 46:
```
AA0002000000000000000003 /* TestPilotShared.xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = TestPilotShared.xcframework; path = "../sdk/testpilot/build/XCFrameworks/debug/TestPilotShared.xcframework"; sourceTree = "<group>"; };
```

Replace with:
```
AA0002000000000000000003 /* TestPilotShared.xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = TestPilotShared.xcframework; path = "$(HOME)/.testpilot/ios/TestPilotShared.xcframework"; sourceTree = "<group>"; };
```

- [ ] **Step 2: Update FRAMEWORK_SEARCH_PATHS in project.pbxproj**

Find the two occurrences of (lines 272 and 291):
```
FRAMEWORK_SEARCH_PATHS = "$(inherited) $(SRCROOT)/../sdk/testpilot/build/XCFrameworks/debug";
```

Replace both with:
```
FRAMEWORK_SEARCH_PATHS = "$(inherited) $(HOME)/.testpilot/ios";
```

- [ ] **Step 3: Update build_ios_sdk.sh to deploy to ~/.testpilot/**

Open `scripts/build_ios_sdk.sh`. After the `./gradlew` line at the end, add:

```bash
# Deploy built artifacts to ~/.testpilot/ so harness can find them
CACHE_DIR="$HOME/.testpilot"
mkdir -p "$CACHE_DIR/ios" "$CACHE_DIR/harness"

# Copy XCFramework
FRAMEWORK_SRC="$(pwd)/testpilot/build/XCFrameworks/debug/TestPilotShared.xcframework"
rm -rf "$CACHE_DIR/ios/TestPilotShared.xcframework"
cp -R "$FRAMEWORK_SRC" "$CACHE_DIR/ios/TestPilotShared.xcframework"

# Copy harness project (everything except the generated .swift file)
rsync -a --exclude="AnalystTests/AnalystTests.swift" \
    "$(cd .. && pwd)/harness/" "$CACHE_DIR/harness/"

echo "Artifacts deployed to $CACHE_DIR"
```

Note: the `./gradlew` in `build_ios_sdk.sh` runs from the `sdk/` directory (the script does `cd sdk` at the end). So the framework path uses `testpilot/build/...` not `sdk/testpilot/build/...`.

The full updated `scripts/build_ios_sdk.sh` should be:

```bash
#! /bin/bash

set +o xtrace

TASK=$1

# Replace Xcode path and create .def files
export XCODE_PATH="$(xcode-select -p)"
export IPHONEOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
export IPHONESIMULATOR_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
export XCTEST_STUB_HEADER="$(pwd)/sdk/testpilot/src/iosMain/xctest_stub.h"

declare -a FILES=("xctest_iosArm64" "xctest_iosSimulatorArm64" "xctest_iosX64")

IFS=
for FILE in ${FILES[@]}; do
  full_path="sdk/testpilot/src/iosMain/$FILE"
  temp=$(cat $full_path.templ | envsubst)
  echo "$temp" > $full_path.def
done

# Build iOS SDK
cd sdk
./gradlew ${TASK:-testpilot:assembleTestPilotSharedDebugXCFramework}

# Deploy built artifacts to ~/.testpilot/ so harness can find them
CACHE_DIR="$HOME/.testpilot"
mkdir -p "$CACHE_DIR/ios" "$CACHE_DIR/harness"

FRAMEWORK_SRC="$(pwd)/testpilot/build/XCFrameworks/debug/TestPilotShared.xcframework"
rm -rf "$CACHE_DIR/ios/TestPilotShared.xcframework"
cp -R "$FRAMEWORK_SRC" "$CACHE_DIR/ios/TestPilotShared.xcframework"

rsync -a --exclude="AnalystTests/AnalystTests.swift" \
    "$(cd .. && pwd)/harness/" "$CACHE_DIR/harness/"

echo "Artifacts deployed to $CACHE_DIR"
```

- [ ] **Step 4: Test the build script deploys correctly**

```bash
cd /Users/leonardo.reis/Projects/WorkCo/testpilot
scripts/build_ios_sdk.sh
ls ~/.testpilot/ios/
ls ~/.testpilot/harness/
```

Expected:
```
~/.testpilot/ios/TestPilotShared.xcframework/
~/.testpilot/harness/Harness.xcodeproj/
~/.testpilot/harness/AnalystTests/     (no .swift file yet — that's generated at runtime)
~/.testpilot/harness/HarnessApp/
```

- [ ] **Step 5: Verify xcodebuild finds the framework from the new path**

Boot a simulator first if none is running:
```bash
xcrun simctl boot "iPhone 16" 2>/dev/null || true
UDID=$(xcrun simctl list devices --json | python3 -c "
import json,sys
devs=json.load(sys.stdin)
for r,ds in devs.get('devices',{}).items():
    for d in ds:
        if d.get('state')=='Booted': print(d['udid']); exit()")
echo "Booted: $UDID"
```

Create a minimal test file and verify xcodebuild resolves the framework:
```bash
mkdir -p ~/.testpilot/harness/AnalystTests
cat > ~/.testpilot/harness/AnalystTests/AnalystTests.swift <<'SWIFT'
import XCTest
import TestPilotShared
class AnalystTests: XCTestCase {
    func testSmoke() { XCTAssertTrue(true) }
}
SWIFT

xcodebuild build-for-testing \
  -project ~/.testpilot/harness/Harness.xcodeproj \
  -scheme AnalystTests \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath /tmp/tp-verify \
  2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED` (no `framework not found` error).

- [ ] **Step 6: Commit**

```bash
git add harness/Harness.xcodeproj/project.pbxproj scripts/build_ios_sdk.sh
git commit -m "build(ios): use ~/.testpilot/ios for harness framework path"
```

---

### Task 3: ArtifactManager.swift

**Files:**
- Create: `mac-app/TestPilotApp/Services/ArtifactManager.swift`

Handles downloading and versioning pre-built artifacts from GitHub releases.

- [ ] **Step 1: Create ArtifactManager.swift**

```swift
// mac-app/TestPilotApp/Services/ArtifactManager.swift
import Foundation
import Observation
import CryptoKit

private let manifestURLString = "https://github.com/workco/testpilot/releases/latest/download/artifacts-manifest.json"
private let artifactDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".testpilot")

// MARK: - Types

struct ArtifactManifest: Decodable {
    struct Entry: Decodable {
        let sha256: String
        let url: String
    }
    let version: String
    let artifacts: [String: Entry]
}

enum ArtifactState: Equatable {
    case unknown
    case checking
    case downloading(artifact: String, progress: Double)
    case ready
    case failed(String)
}

enum ArtifactError: LocalizedError {
    case sha256Mismatch(expected: String, actual: String)
    case unpackFailed(Int32)
    case noArtifactsOffline

    var errorDescription: String? {
        switch self {
        case .sha256Mismatch(let e, let a):
            return "Integrity check failed — expected \(e), got \(a)"
        case .unpackFailed(let code):
            return "Failed to unpack artifact (exit \(code))"
        case .noArtifactsOffline:
            return "Could not reach GitHub to download components. Connect to the internet and relaunch."
        }
    }
}

// MARK: - ArtifactManager

@MainActor
@Observable
final class ArtifactManager {
    private(set) var state: ArtifactState = .unknown

    var isReady: Bool { state == .ready }

    func ensureArtifacts() async {
        state = .checking

        guard let manifestURL = URL(string: manifestURLString) else { return }

        let manifest: ArtifactManifest
        let manifestData: Data
        do {
            (manifestData, _) = try await URLSession.shared.data(from: manifestURL)
            manifest = try JSONDecoder().decode(ArtifactManifest.self, from: manifestData)
        } catch {
            // Offline: proceed if artifacts already exist locally
            if artifactsExistLocally() {
                state = .ready
            } else {
                state = .failed(ArtifactError.noArtifactsOffline.localizedDescription!)
            }
            return
        }

        // Persist manifest for staleness checks
        let localManifestPath = artifactDir.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        try? manifestData.write(to: localManifestPath)

        // Download each artifact that is missing or outdated
        for (key, entry) in manifest.artifacts.sorted(by: { $0.key < $1.key }) {
            guard needsDownload(key: key, expectedSHA256: entry.sha256) else { continue }
            guard let url = URL(string: entry.url) else { continue }
            state = .downloading(artifact: key, progress: 0)
            do {
                try await download(key: key, from: url, expectedSHA256: entry.sha256)
            } catch {
                state = .failed("Failed to download \(key): \(error.localizedDescription)")
                return
            }
        }

        state = .ready
    }

    // MARK: - Private

    private func artifactsExistLocally() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: artifactDir
            .appendingPathComponent("ios/TestPilotShared.xcframework").path) &&
               fm.fileExists(atPath: artifactDir
            .appendingPathComponent("web/testpilot-web.jar").path)
    }

    private func needsDownload(key: String, expectedSHA256: String) -> Bool {
        let markerPath = artifactDir.appendingPathComponent("\(key)/.sha256")
        guard let saved = try? String(contentsOf: markerPath, encoding: .utf8),
              saved.trimmingCharacters(in: .whitespacesAndNewlines) == expectedSHA256
        else { return true }
        return false
    }

    private func download(key: String, from url: URL, expectedSHA256: String) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("testpilot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempFile = tempDir.appendingPathComponent(url.lastPathComponent)

        // Download (URLSession gives us a temp file)
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: downloadedURL, to: tempFile)

        // Verify SHA256
        let fileData = try Data(contentsOf: tempFile)
        let hash = SHA256.hash(data: fileData)
            .map { String(format: "%02x", $0) }.joined()
        guard hash == expectedSHA256 else {
            throw ArtifactError.sha256Mismatch(expected: expectedSHA256, actual: hash)
        }

        // Unpack into ~/.testpilot/<key>/
        let destDir = artifactDir.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: destDir)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let filename = url.lastPathComponent
        if filename.hasSuffix(".zip") {
            try runCommand("/usr/bin/unzip", args: ["-q", tempFile.path, "-d", destDir.path])
        } else if filename.hasSuffix(".tar.gz") {
            try runCommand("/usr/bin/tar", args: ["-xzf", tempFile.path, "-C", destDir.path])
        }

        // Write SHA256 marker so future launches skip this artifact
        let markerPath = destDir.appendingPathComponent(".sha256")
        try expectedSHA256.write(to: markerPath, atomically: true, encoding: .utf8)
    }

    private func runCommand(_ executable: String, args: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ArtifactError.unpackFailed(proc.terminationStatus)
        }
    }
}
```

- [ ] **Step 2: Build the Mac app to verify ArtifactManager compiles**

Open the Mac app in Xcode (or run via `xcodebuild`):

```bash
xcodebuild build \
  -project mac-app/TestPilotApp.xcodeproj \
  -scheme TestPilotApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` (no errors in ArtifactManager.swift).

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Services/ArtifactManager.swift
git commit -m "feat(mac): add ArtifactManager for artifact download and versioning"
```

---

### Task 4: IOSRunner.swift

**Files:**
- Create: `mac-app/TestPilotApp/Services/IOSRunner.swift`

Handles iOS-specific orchestration: bundle ID resolution, test file generation, and xcodebuild Process setup. Replicates the logic currently in the `testpilot` bash script lines 123–297.

- [ ] **Step 1: Create IOSRunner.swift**

```swift
// mac-app/TestPilotApp/Services/IOSRunner.swift
import Foundation

private let cacheDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".testpilot")

enum IOSRunnerError: LocalizedError {
    case xcodebuildNotFound
    case bundleIdNotFound(String)
    case multipleBundleIdMatches([String])
    case harnessNotFound

    var errorDescription: String? {
        switch self {
        case .xcodebuildNotFound:
            return "Xcode is not installed. Install Xcode from the App Store, then relaunch TestPilot."
        case .bundleIdNotFound(let name):
            return "No app matching \"\(name)\" found on the target device."
        case .multipleBundleIdMatches(let choices):
            return "Multiple apps match. Pick a bundle ID: \(choices.joined(separator: ", "))"
        case .harnessNotFound:
            return "TestPilot components not found. Click \"Check for Updates\" in Settings."
        }
    }
}

struct IOSRunner {
    let config: RunConfig
    let settings: SettingsStore

    // MARK: - Public API

    static func isXcodebuildAvailable() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["xcodebuild", "-version"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        return (try? proc.run()) != nil && { proc.waitUntilExit(); return proc.terminationStatus == 0 }()
    }

    /// Resolves the bundle ID for config.appName on config.selectedDevice.
    func resolveBundleId() async throws -> String {
        guard let device = config.selectedDevice else {
            throw IOSRunnerError.bundleIdNotFound(config.appName)
        }

        let rawOutput: String
        if device.isPhysical {
            rawOutput = try await listAppsOnDevice(udid: device.id)
        } else {
            rawOutput = try await listAppsOnSimulator(udid: device.id)
        }

        return try pickBundleId(from: rawOutput, appName: config.appName)
    }

    /// Writes AnalystTests.swift to ~/.testpilot/harness/AnalystTests/ with this run's config.
    func generateTestFile(bundleId: String) throws {
        let testSwiftURL = cacheDir
            .appendingPathComponent("harness/AnalystTests/AnalystTests.swift")
        try FileManager.default.createDirectory(
            at: testSwiftURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let content = buildTestSwift(bundleId: bundleId)
        try content.write(to: testSwiftURL, atomically: true, encoding: .utf8)
    }

    /// Returns a configured xcodebuild Process. Call process.run() to start it.
    func makeProcess() throws -> Process {
        let harnessProject = cacheDir.appendingPathComponent("harness/Harness.xcodeproj")
        guard FileManager.default.fileExists(atPath: harnessProject.path) else {
            throw IOSRunnerError.harnessNotFound
        }

        guard let device = config.selectedDevice else {
            throw IOSRunnerError.bundleIdNotFound(config.appName)
        }

        let destination = device.isPhysical
            ? "platform=iOS,id=\(device.id)"
            : "platform=iOS Simulator,id=\(device.id)"

        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("testpilot-derived-\(UUID().uuidString)")

        var args = [
            "test",
            "-project",         harnessProject.path,
            "-scheme",          "AnalystTests",
            "-destination",     destination,
            "-derivedDataPath", derivedData.path,
        ]

        if device.isPhysical && !settings.teamId.isEmpty {
            args += ["-allowProvisioningUpdates", "DEVELOPMENT_TEAM=\(settings.teamId)"]
        }

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        proc.arguments = args
        proc.environment = env
        return proc
    }

    // MARK: - Bundle ID resolution

    private func listAppsOnSimulator(udid: String) async throws -> String {
        try await runProcess(
            "/usr/bin/xcrun",
            args: ["simctl", "listapps", udid])
    }

    private func listAppsOnDevice(udid: String) async throws -> String {
        let tempJSON = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp_apps_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempJSON) }
        _ = try? await runProcess(
            "/usr/bin/xcrun",
            args: ["devicectl", "device", "info", "apps",
                   "--device", udid, "--json-output", tempJSON.path])
        return (try? String(contentsOf: tempJSON, encoding: .utf8)) ?? ""
    }

    private func pickBundleId(from output: String, appName: String) throws -> String {
        let nameLower = appName.lowercased()
        var matches: [String] = []

        // Simulator: ASCII plist format — look for bundle IDs containing app name
        // Pattern: lines like `"com.example.app" = {` followed by CFBundleDisplayName
        // Simple heuristic: find all bundle IDs (contain a dot, appear as keys)
        let bundlePattern = #""([a-zA-Z0-9.\-]+)"\s*=\s*\{"#
        if let regex = try? NSRegularExpression(pattern: bundlePattern) {
            let range = NSRange(output.startIndex..., in: output)
            let allMatches = regex.matches(in: output, range: range)
            let candidates = allMatches.compactMap { m -> String? in
                guard let r = Range(m.range(at: 1), in: output) else { return nil }
                return String(output[r])
            }
            for bid in candidates {
                if bid.lowercased().contains(nameLower) || nameLower.contains(bid.lowercased().components(separatedBy: ".").last ?? "") {
                    matches.append(bid)
                }
            }
        }

        // Device: JSON format from devicectl
        if matches.isEmpty, let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [String: Any],
           let apps = result["apps"] as? [[String: Any]] {
            for app in apps {
                let bid = (app["bundleIdentifier"] ?? app["bundleID"]) as? String ?? ""
                let name = app["name"] as? String ?? bid
                if name.lowercased().contains(nameLower) || bid.lowercased().contains(nameLower) {
                    matches.append(bid)
                }
            }
        }

        switch matches.count {
        case 0: throw IOSRunnerError.bundleIdNotFound(appName)
        case 1: return matches[0]
        default: throw IOSRunnerError.multipleBundleIdMatches(Array(Set(matches)))
        }
    }

    // MARK: - Test file generation

    private func buildTestSwift(bundleId: String) -> String {
        let provider = (config.providerOverride ?? settings.provider).rawValue
        let apiKey   = swiftEsc(settings.apiKey)
        let provEsc  = swiftEsc(provider)
        let objEsc   = swiftEsc(config.objective)
        let langEsc  = swiftEsc(config.language.rawValue)
        let bidOpt   = bundleId.isEmpty ? "nil" : "\"\(swiftEsc(bundleId))\""
        let userOpt  = config.username.isEmpty ? "nil" : "\"\(swiftEsc(config.username))\""
        let passOpt  = config.password.isEmpty ? "nil" : "\"\(swiftEsc(config.password))\""
        let xcAppInit = bundleId.isEmpty
            ? "XCUIApplication()"
            : "XCUIApplication(bundleIdentifier: \(bidOpt))"

        let providerExpr = """
"\\(provEsc)" == "openai" ? .openai : ("\\(provEsc)" == "gemini" ? .gemini : .anthropic)
"""

        if config.mode == .test {
            return """
// This file is overwritten by TestPilot before each run. Do not edit manually.
import XCTest
import TestPilotShared

class AnalystTests: XCTestCase {
    var analyst: TestAnalystIOS!
    var xcApp: XCUIApplication!

    override func setUp() {
        super.setUp()
        xcApp = \(xcAppInit)
        let provider: AIProvider = \(providerExpr)
        let config = ConfigBuilder()
            .provider(provider: provider)
            .apiKey(key: "\(apiKey)")
            .maxSteps(steps: \(config.maxSteps))
            .language(lang: "\(langEsc)")
            .build()
        analyst = TestAnalystIOS(config: config)
    }

    func testAnalyze() async throws {
        let _ = try await analyst.run(
            objective: "\(objEsc)",
            xcApp: xcApp,
            username: \(userOpt),
            password: \(passOpt)
        )
    }
}
"""
        } else {
            return """
// This file is overwritten by TestPilot before each run. Do not edit manually.
import XCTest
import TestPilotShared

class AnalystTests: XCTestCase {
    var analyst: AnalystIOS!
    var xcApp: XCUIApplication!

    override func setUp() {
        super.setUp()
        xcApp = \(xcAppInit)
        let provider: AIProvider = \(providerExpr)
        let config = ConfigBuilder()
            .provider(provider: provider)
            .apiKey(key: "\(apiKey)")
            .maxSteps(steps: \(config.maxSteps))
            .language(lang: "\(langEsc)")
            .build()
        analyst = AnalystIOS(config: config)
    }

    func testAnalyze() async throws {
        let _ = try await analyst.run(
            objective: "\(objEsc)",
            xcApp: xcApp,
            username: \(userOpt),
            password: \(passOpt)
        )
    }
}
"""
        }
    }

    // MARK: - Helpers

    private func swiftEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }

    private func runProcess(_ executable: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = FileHandle.nullDevice
            proc.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try proc.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
```

- [ ] **Step 2: Build the Mac app to verify IOSRunner.swift compiles**

```bash
xcodebuild build \
  -project mac-app/TestPilotApp.xcodeproj \
  -scheme TestPilotApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Services/IOSRunner.swift
git commit -m "feat(mac): add IOSRunner — bundle ID resolution and xcodebuild process setup"
```

---

### Task 5: WebRunner.swift

**Files:**
- Create: `mac-app/TestPilotApp/Services/WebRunner.swift`

Sets up the `java -jar` process for the web runner. Mirrors the env var passing from the CLI's web platform section (lines 505–516 of `testpilot`).

- [ ] **Step 1: Create WebRunner.swift**

```swift
// mac-app/TestPilotApp/Services/WebRunner.swift
import Foundation

private let cacheDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".testpilot")

enum WebRunnerError: LocalizedError {
    case jarNotFound
    case jreNotFound

    var errorDescription: String? {
        switch self {
        case .jarNotFound:
            return "Web runner not found. Click \"Check for Updates\" in Settings."
        case .jreNotFound:
            return "Java runtime not found. Click \"Check for Updates\" in Settings."
        }
    }
}

struct WebRunner {
    let config: RunConfig
    let settings: SettingsStore

    func makeProcess() throws -> Process {
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        let provider = (config.providerOverride ?? settings.provider).rawValue
        let outputPath = NSString(string: config.outputPath).expandingTildeInPath

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]         = config.mode.rawValue
        env["TESTPILOT_WEB_URL"]      = config.url
        env["TESTPILOT_OBJECTIVE"]    = config.objective
        env["TESTPILOT_API_KEY"]      = settings.apiKey
        env["TESTPILOT_PROVIDER"]     = provider
        env["TESTPILOT_MAX_STEPS"]    = "\(config.maxSteps)"
        env["TESTPILOT_LANG"]         = config.language.rawValue
        env["TESTPILOT_OUTPUT"]       = outputPath
        env["TESTPILOT_WEB_USERNAME"] = config.username
        env["TESTPILOT_WEB_PASSWORD"] = config.password

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }

    func makeWebLoginProcess() throws -> Process {
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        let provider = (config.providerOverride ?? settings.provider).rawValue

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]     = "login"
        env["TESTPILOT_WEB_URL"]  = config.url
        env["TESTPILOT_API_KEY"]  = settings.apiKey.isEmpty ? "dummy" : settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }
}
```

- [ ] **Step 2: Build the Mac app to verify WebRunner.swift compiles**

```bash
xcodebuild build \
  -project mac-app/TestPilotApp.xcodeproj \
  -scheme TestPilotApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Services/WebRunner.swift
git commit -m "feat(mac): add WebRunner — java -jar process setup for web platform"
```

---

### Task 6: Refactor AnalysisRunner.swift

**Files:**
- Modify: `mac-app/TestPilotApp/Services/AnalysisRunner.swift`

Three changes:
1. Remove the `scriptURL` resolution logic from `run()` and `webLogin()`
2. Delegate to `IOSRunner`/`WebRunner` for process creation
3. Fix marker parsing — raw xcodebuild output embeds markers mid-line (e.g. `t = 52s  TestPilot TESTPILOT_STEP: foo`), so use `range(of:)` instead of `hasPrefix()`

- [ ] **Step 1: Replace run() method**

Replace the entire `run(config:settings:)` method (lines 30–198 of the current file) with:

```swift
func run(config: RunConfig, settings: SettingsStore) {
    guard case .idle = state else { return }

    if settings.apiKey.isEmpty {
        state = .failed(error: "API key not set — open Settings and enter your API key")
        return
    }

    let outputPath = NSString(string: config.outputPath).expandingTildeInPath
    lastStdoutLine = ""
    analyzeSteps = []
    state = config.mode == .test ? .testRunning(steps: []) : .running(statusLine: "Starting…")

    Task {
        do {
            let proc: Process
            switch config.platform {
            case .ios:
                guard IOSRunner.isXcodebuildAvailable() else {
                    await MainActor.run { state = .failed(error: IOSRunnerError.xcodebuildNotFound.localizedDescription!) }
                    return
                }
                let runner = IOSRunner(config: config, settings: settings)
                let bundleId = try await runner.resolveBundleId()
                try runner.generateTestFile(bundleId: bundleId)
                proc = try runner.makeProcess()
            case .web:
                proc = try WebRunner(config: config, settings: settings).makeProcess()
            case .android:
                await MainActor.run {
                    state = .failed(error: "Android support coming soon. Use the CLI for Android.")
                }
                return
            }
            await MainActor.run { self.startProcess(proc, outputPath: outputPath) }
        } catch {
            await MainActor.run { state = .failed(error: error.localizedDescription) }
        }
    }
}
```

- [ ] **Step 2: Extract process start + stdout handling into startProcess()**

Add a new private method `startProcess(_:outputPath:)` that contains the Process setup that was previously inline in `run()`. The stdout handler needs to use `range(of:)` instead of `hasPrefix()` because xcodebuild wraps markers mid-line:

```swift
private func startProcess(_ p: Process, outputPath: String) {
    let stdout = Pipe()
    let stderr = Pipe()
    p.standardOutput = stdout
    p.standardError  = stderr

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            DispatchQueue.main.async {
                guard let self else { return }
                self.lastStdoutLine = line

                // Use range(of:) — xcodebuild embeds markers mid-line
                if let r = line.range(of: "TESTPILOT_STEP: ") {
                    let msg = String(line[r.upperBound...])
                    let cached = msg.hasPrefix("(cached)")
                    let clean = cached ? String(msg.dropFirst("(cached) ".count)) : msg
                    let step = TestStep(message: clean, cached: cached)
                    withAnimation(.easeInOut(duration: 0.4)) {
                        switch self.state {
                        case .testRunning(let steps):
                            self.state = .testRunning(steps: steps + [step])
                        case .running:
                            self.analyzeSteps.append(step)
                            self.state = .running(statusLine: clean)
                        default: break
                        }
                    }
                } else if let r = line.range(of: "TESTPILOT_RESULT: ") {
                    let payload = String(line[r.upperBound...])
                    let steps: [TestStep]
                    if case .testRunning(let s) = self.state { steps = s } else { steps = [] }
                    if payload.hasPrefix("PASS ") {
                        self.state = .testPassed(reason: String(payload.dropFirst("PASS ".count)), steps: steps)
                    } else if payload.hasPrefix("FAIL ") {
                        self.state = .testFailed(reason: String(payload.dropFirst("FAIL ".count)), steps: steps)
                    }
                } else if let r = line.range(of: "TESTPILOT_REPORT_PATH=") {
                    // Store report path for termination handler
                    self.lastReportPath = String(line[r.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    if case .running = self.state {
                        self.state = .running(statusLine: line)
                    }
                }
            }
        }
    }

    p.terminationHandler = { [weak self] proc in
        stdout.fileHandleForReading.readabilityHandler = nil
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let lastStderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DispatchQueue.main.async {
            guard let self else { return }
            switch self.state {
            case .running:
                if proc.terminationStatus == 0 {
                    // Use report path from marker if available, else default outputPath
                    let path = self.lastReportPath.isEmpty ? outputPath : self.lastReportPath
                    self.state = .completed(reportPath: path)
                    self.lastReportPath = ""
                } else {
                    let fallback = self.lastStdoutLine
                    let msg = !lastStderr.isEmpty ? lastStderr
                            : !fallback.isEmpty    ? fallback
                            : "Analysis failed (exit \(proc.terminationStatus))"
                    self.state = .failed(error: msg)
                }
            case .testRunning(let steps):
                let fallback = self.lastStdoutLine
                let msg = !lastStderr.isEmpty ? lastStderr
                        : !fallback.isEmpty    ? fallback
                        : "Test failed (exit \(proc.terminationStatus))"
                self.state = .testFailed(reason: msg, steps: steps)
            default: break
            }
        }
    }

    process = p
    do { try p.run() } catch {
        state = .failed(error: error.localizedDescription)
    }
}
```

- [ ] **Step 3: Add lastReportPath property**

Add to the `AnalysisRunner` class properties:

```swift
private var lastReportPath: String = ""
```

- [ ] **Step 4: Replace webLogin() to use WebRunner**

Replace the `webLogin(config:settings:)` method with:

```swift
func webLogin(config: RunConfig, settings: SettingsStore) {
    guard case .idle = state else { return }

    Task {
        do {
            let proc = try WebRunner(config: config, settings: settings).makeWebLoginProcess()
            await MainActor.run { self.startWebLoginProcess(proc) }
        } catch {
            await MainActor.run { state = .failed(error: error.localizedDescription) }
        }
    }
}
```

- [ ] **Step 5: Rename the existing webLogin process-start logic to startWebLoginProcess()**

Extract the `Process` setup from the old `webLogin` body into `startWebLoginProcess(_ p: Process)`. Keep the stdin pipe and `TESTPILOT_LOGIN_READY` / `TESTPILOT_LOGIN_DONE:` parsing unchanged:

```swift
private func startWebLoginProcess(_ p: Process) {
    let stdin  = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    p.standardInput  = stdin
    p.standardOutput = stdout
    p.standardError  = stderr

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            DispatchQueue.main.async {
                guard let self else { return }
                if trimmed == "TESTPILOT_LOGIN_READY" {
                    self.state = .webLoginPending
                } else if trimmed.hasPrefix("TESTPILOT_LOGIN_DONE:") {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    self.state = .idle
                }
            }
        }
    }

    p.terminationHandler = { [weak self] proc in
        stdout.fileHandleForReading.readabilityHandler = nil
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let lastStderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DispatchQueue.main.async {
            guard let self else { return }
            if case .webLoginPending = self.state {
                self.state = .idle
            } else if case .running = self.state {
                let msg = !lastStderr.isEmpty ? lastStderr
                        : "web-login process exited unexpectedly (exit \(proc.terminationStatus))"
                self.state = .failed(error: msg)
            }
        }
    }

    state = .running(statusLine: "Opening browser for login…")
    process = p
    do { try p.run() } catch {
        state = .failed(error: error.localizedDescription)
    }
}
```

- [ ] **Step 6: Build the Mac app**

```bash
xcodebuild build \
  -project mac-app/TestPilotApp.xcodeproj \
  -scheme TestPilotApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add mac-app/TestPilotApp/Services/AnalysisRunner.swift
git commit -m "feat(mac): refactor AnalysisRunner to use IOSRunner/WebRunner, fix marker parsing"
```

---

### Task 7: Remove scriptPath from SettingsStore and SettingsView

**Files:**
- Modify: `mac-app/TestPilotApp/Services/SettingsStore.swift`
- Modify: `mac-app/TestPilotApp/Views/SettingsView.swift`

- [ ] **Step 1: Remove scriptPath from SettingsStore.swift**

In `SettingsStore.swift`:

Remove the property:
```swift
var scriptPath: String = ""
```

Remove the constant:
```swift
private let scriptPathKey = "tp_scriptPath"
```

Remove from `init()`:
```swift
scriptPath = UserDefaults.standard.string(forKey: "tp_scriptPath")
    ?? SettingsStore.discoverScriptPath()
    ?? ""
```

Remove from `save()`:
```swift
UserDefaults.standard.set(scriptPath, forKey: scriptPathKey)
```

Remove the entire `discoverScriptPath()` static method (lines 117–150).

- [ ] **Step 2: Remove Script section from SettingsView.swift**

In `SettingsView.swift`, remove the entire `Section` block containing the script path `TextField` and `Browse…` button (lines 34–57):

```swift
// Delete this entire block:
Section {
    HStack {
        TextField("testpilot script path", text: $store.scriptPath)
            .onChange(of: store.scriptPath) { _, _ in store.save() }
        Button("Browse…") { ... }
            .buttonStyle(.bordered)
    }
} header: {
    Text("Script")
} footer: {
    Text("Path to the testpilot script in your repo...")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Add a "Check for updates" button in the existing footer area. In the `.env` section footer, add below the existing footer text:

```swift
Section {
    DisclosureGroup(".env file  (~/.testpilot/.env)", isExpanded: $showRawEnv) {
        TextEditor(text: $rawEnvText)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 90)
            .scrollContentBackground(.hidden)
            .onChange(of: rawEnvText) { _, v in
                store.rawEnv = v
                store.save()
                apiKeyText = store.apiKey
            }
    }
} footer: {
    Text("Edits here sync with the fields above and are written to disk for use with the CLI.")
        .font(.caption)
        .foregroundStyle(.secondary)
}

Section {
    Button("Check for Updates") {
        onCheckForUpdates?()
    }
} footer: {
    Text("Downloads the latest TestPilot components to ~/.testpilot/.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Add the callback property at the top of `SettingsView`:
```swift
var onCheckForUpdates: (() -> Void)? = nil
```

- [ ] **Step 3: Build the Mac app**

```bash
xcodebuild build \
  -project mac-app/TestPilotApp.xcodeproj \
  -scheme TestPilotApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add mac-app/TestPilotApp/Services/SettingsStore.swift \
        mac-app/TestPilotApp/Views/SettingsView.swift
git commit -m "feat(mac): remove script path setting — no longer needed"
```

---

### Task 8: ContentView — ArtifactManager + setup sheet

**Files:**
- Modify: `mac-app/TestPilotApp/Views/ContentView.swift`

Wire `ArtifactManager` into the app lifecycle: check artifacts on launch, block the UI with a setup sheet while downloading, surface "Check for Updates" from Settings.

- [ ] **Step 1: Update ContentView.swift**

Replace the entire `ContentView.swift` with:

```swift
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case newRun  = "New Run"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .newRun:    return "plus.circle"
        case .history:   return "clock"
        case .settings:  return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .newRun
    @State private var config           = RunConfig()
    @State private var runner           = AnalysisRunner()
    @State private var settings         = SettingsStore()
    @State private var history          = HistoryStore()
    @State private var detector         = DeviceDetector()
    @State private var artifactManager  = ArtifactManager()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 180)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 440)
        }
        .task { await artifactManager.ensureArtifacts() }
        .sheet(isPresented: .constant(!artifactManager.isReady)) {
            SetupSheet(manager: artifactManager)
        }
        .onChange(of: runner.state) { _, newState in
            let displayName = config.platform == .web ? config.url : config.appName
            switch newState {
            case .completed(let path):
                history.append(RunRecord(appName: displayName, platform: config.platform,
                                         objective: config.objective, reportPath: path, mode: .analyze))
            case .testPassed(let reason, _):
                history.append(RunRecord(appName: displayName, platform: config.platform,
                                         objective: config.objective, reportPath: "",
                                         mode: .test, testOutcome: TestOutcome(passed: true, reason: reason)))
            case .testFailed(let reason, _):
                history.append(RunRecord(appName: displayName, platform: config.platform,
                                         objective: config.objective, reportPath: "",
                                         mode: .test, testOutcome: TestOutcome(passed: false, reason: reason)))
            default: break
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .newRun, .none:
            switch runner.state {
            case .idle:
                RunView(config: config, detector: detector, settings: settings, runner: runner)
            default:
                RunningView(runner: runner, config: config)
            }
        case .history:
            HistoryView(store: history)
        case .settings:
            SettingsView(store: settings, onCheckForUpdates: {
                Task { await artifactManager.ensureArtifacts() }
            })
        }
    }
}

// MARK: - Setup sheet shown while artifacts are being downloaded

struct SetupSheet: View {
    let manager: ArtifactManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Setting up TestPilot")
                .font(.title2.bold())

            content
        }
        .padding(40)
        .frame(width: 400)
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .checking:
            ProgressView("Checking for updates…")
        case .downloading(let artifact, let progress):
            VStack(spacing: 8) {
                Text("Downloading \(artifact)…")
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        case .failed(let msg):
            VStack(spacing: 12) {
                Text(msg)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await manager.ensureArtifacts() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            // Sheet dismissed via .constant(!manager.isReady) — nothing to show
            EmptyView()
        case .unknown:
            ProgressView()
        }
    }
}
```

- [ ] **Step 2: Build and run the Mac app**

```bash
xcodebuild build \
  -project mac-app/TestPilotApp.xcodeproj \
  -scheme TestPilotApp \
  -destination "platform=macOS" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual smoke test**

Open the app. On first launch (before any GitHub release exists), the sheet should show. The retry button should be visible if the manifest fetch fails. Once `~/.testpilot/ios/` and `~/.testpilot/web/` exist, the sheet should not appear.

To simulate ready state for testing:
```bash
mkdir -p ~/.testpilot/ios ~/.testpilot/web
touch ~/.testpilot/web/testpilot-web.jar
```

Then re-launch the app — the sheet should not appear (artifacts exist locally, offline fallback kicks in).

- [ ] **Step 4: Commit**

```bash
git add mac-app/TestPilotApp/Views/ContentView.swift
git commit -m "feat(mac): add ArtifactManager and setup sheet for first-run download"
```

---

### Task 9: Update testpilot CLI

**Files:**
- Modify: `testpilot`

Replace iOS `build_ios_sdk.sh` + Gradle web calls with `_ensure_artifact` helper and direct java/xcodebuild invocations from `~/.testpilot/`.

- [ ] **Step 1: Add TESTPILOT_CACHE variable and _ensure_artifact function**

After the `SCRIPT_DIR` line (line 64), add:

```bash
TESTPILOT_CACHE="$HOME/.testpilot"
MANIFEST_URL="https://github.com/workco/testpilot/releases/latest/download/artifacts-manifest.json"

_ensure_artifact() {
  local platform="$1"
  local dest="$TESTPILOT_CACHE/$platform"

  # If artifact already exists locally, use it (no version check in CLI)
  case "$platform" in
    ios)
      [[ -d "$dest/TestPilotShared.xcframework" && -d "$TESTPILOT_CACHE/harness/Harness.xcodeproj" ]] && return 0
      ;;
    web)
      [[ -f "$dest/testpilot-web.jar" && -x "$dest/jre/bin/java" ]] && return 0
      ;;
  esac

  echo "Downloading $platform components..."

  # Fetch manifest
  local manifest
  manifest=$(curl -fsSL "$MANIFEST_URL" 2>/dev/null) \
    || { echo "Error: Could not download artifacts manifest. Check your internet connection."; exit 1; }

  local url sha256
  url=$(echo "$manifest" | python3 -c "import json,sys; m=json.load(sys.stdin); print(m['artifacts']['$platform']['url'])")
  sha256=$(echo "$manifest" | python3 -c "import json,sys; m=json.load(sys.stdin); print(m['artifacts']['$platform']['sha256'])")

  [[ -z "$url" ]] && { echo "Error: No artifact URL for platform $platform in manifest."; exit 1; }

  # Download to temp file
  local tmp
  tmp=$(mktemp /tmp/testpilot_artifact_XXXXXX)
  trap 'rm -f "$tmp"' RETURN
  curl -fL --progress-bar "$url" -o "$tmp" \
    || { echo "Error: Failed to download $url"; exit 1; }

  # Verify SHA256
  local actual
  actual=$(shasum -a 256 "$tmp" | awk '{print $1}')
  [[ "$actual" == "$sha256" ]] || { echo "Error: SHA256 mismatch for $platform artifact."; exit 1; }

  # Unpack
  mkdir -p "$dest"
  case "$url" in
    *.zip)    unzip -q "$tmp" -d "$dest" ;;
    *.tar.gz) tar -xzf "$tmp" -C "$dest" ;;
  esac

  echo "$sha256" > "$dest/.sha256"
  echo "$platform components ready."
}
```

- [ ] **Step 2: Update iOS section — replace build_ios_sdk.sh call**

Find the iOS build section (around line 193–196):

```bash
  # ── Build SDK ────────────────────────────────────────────────────────────────
  echo "Building SDK..."
  (cd "$SCRIPT_DIR" && scripts/build_ios_sdk.sh) >/dev/null 2>&1 \
    || { echo "Error: SDK build failed. Run scripts/build_ios_sdk.sh manually for details."; exit 1; }
```

Replace with:

```bash
  # ── Ensure artifacts present ─────────────────────────────────────────────────
  _ensure_artifact ios
```

- [ ] **Step 3: Update iOS section — harness path**

Find lines 199–203 where `DERIVED_DATA` and `TEST_SWIFT` are set:

```bash
  DERIVED_DATA=$(mktemp -d)
  TEST_SWIFT="$SCRIPT_DIR/harness/AnalystTests/AnalystTests.swift"
  TEST_SWIFT_BACKUP="$SCRIPT_DIR/harness/AnalystTests/AnalystTests.swift.bak"
  cp "$TEST_SWIFT" "$TEST_SWIFT_BACKUP"
  trap 'cp "$TEST_SWIFT_BACKUP" "$TEST_SWIFT"; rm -f "$TEST_SWIFT_BACKUP"; ...
```

Replace with:

```bash
  DERIVED_DATA=$(mktemp -d)
  TEST_SWIFT="$TESTPILOT_CACHE/harness/AnalystTests/AnalystTests.swift"
  mkdir -p "$(dirname "$TEST_SWIFT")"
  # No backup needed — file is always regenerated, not precious
  trap '[[ -f "$DERIVED_DATA/xcodebuild.log" ]] && cp "$DERIVED_DATA/xcodebuild.log" /tmp/testpilot_last_xcodebuild.log; rm -rf "$DERIVED_DATA"' EXIT
```

- [ ] **Step 4: Update xcodebuild invocation to use ~/.testpilot/harness**

Find the xcodebuild line (around line 315):
```bash
  xcodebuild test \
      -project "$SCRIPT_DIR/harness/Harness.xcodeproj" \
```

Replace with:
```bash
  xcodebuild test \
      -project "$TESTPILOT_CACHE/harness/Harness.xcodeproj" \
```

- [ ] **Step 5: Update web section — replace Gradle calls**

Find the web section (around lines 488–519). Replace:

```bash
elif [[ "$PLATFORM" == "web" ]]; then
  command -v java >/dev/null 2>&1 || { echo "Error: java not found — install JDK 11+"; exit 1; }

  echo "Building web runner..."
  (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:jvmMainClasses) \
    || { echo "Error: JVM build failed."; exit 1; }

  # Install Playwright browsers on first run
  if [[ ! -d "$HOME/.cache/ms-playwright" && ! -d "$HOME/Library/Caches/ms-playwright" ]]; then
    echo "Installing Playwright browsers (first time only)..."
    (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:installPlaywrightBrowsers) \
      || { echo "Error: Could not install Playwright browsers."; exit 1; }
  fi

  WEB_LOG=$(mktemp)
  WEB_EXIT_FILE=$(mktemp)
  trap 'rm -f "$WEB_LOG" "$WEB_EXIT_FILE"' EXIT

  (
    export TESTPILOT_MODE="$COMMAND"
    export TESTPILOT_WEB_URL="$URL"
    export TESTPILOT_OBJECTIVE="$OBJECTIVE"
    export TESTPILOT_API_KEY="$API_KEY"
    export TESTPILOT_PROVIDER="$PROVIDER"
    export TESTPILOT_MAX_STEPS="$MAX_STEPS"
    export TESTPILOT_LANG="$LANG_CODE"
    export TESTPILOT_OUTPUT="$OUTPUT"
    export TESTPILOT_WEB_USERNAME="$USERNAME"
    export TESTPILOT_WEB_PASSWORD="$PASSWORD"
    cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:runWebRunner 2>&1
    echo $? >"$WEB_EXIT_FILE"
  ) | grep -v -E "^(FAILURE:|> Run with|> Get more help at|Execution failed for task|> Process '.*' finished with non-zero|BUILD FAILED|\* What went wrong:|\* Try:|[0-9]+ actionable task)" \
    | tee "$WEB_LOG"
  RUNNER_EXIT=$(cat "$WEB_EXIT_FILE" 2>/dev/null || echo "1")
```

With:

```bash
elif [[ "$PLATFORM" == "web" ]]; then
  _ensure_artifact web
  JAVA_BIN="$TESTPILOT_CACHE/web/jre/bin/java"
  WEB_JAR="$TESTPILOT_CACHE/web/testpilot-web.jar"

  WEB_LOG=$(mktemp)
  WEB_EXIT_FILE=$(mktemp)
  trap 'rm -f "$WEB_LOG" "$WEB_EXIT_FILE"' EXIT

  (
    export TESTPILOT_MODE="$COMMAND"
    export TESTPILOT_WEB_URL="$URL"
    export TESTPILOT_OBJECTIVE="$OBJECTIVE"
    export TESTPILOT_API_KEY="$API_KEY"
    export TESTPILOT_PROVIDER="$PROVIDER"
    export TESTPILOT_MAX_STEPS="$MAX_STEPS"
    export TESTPILOT_LANG="$LANG_CODE"
    export TESTPILOT_OUTPUT="$OUTPUT"
    export TESTPILOT_WEB_USERNAME="$USERNAME"
    export TESTPILOT_WEB_PASSWORD="$PASSWORD"
    "$JAVA_BIN" -jar "$WEB_JAR" 2>&1
    echo $? >"$WEB_EXIT_FILE"
  ) | tee "$WEB_LOG"
  RUNNER_EXIT=$(cat "$WEB_EXIT_FILE" 2>/dev/null || echo "1")
```

- [ ] **Step 6: Update web-login section**

Find (lines 69–84):
```bash
  echo "Building web runner..."
  (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:jvmMainClasses) \
    || { echo "Error: JVM build failed."; exit 1; }

  (
    export TESTPILOT_MODE="login"
    ...
    cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:runWebRunner
  )
```

Replace with:
```bash
  _ensure_artifact web
  JAVA_BIN="$TESTPILOT_CACHE/web/jre/bin/java"
  WEB_JAR="$TESTPILOT_CACHE/web/testpilot-web.jar"

  (
    export TESTPILOT_MODE="login"
    export TESTPILOT_WEB_URL="$URL"
    export TESTPILOT_API_KEY="${API_KEY:-dummy}"
    "$JAVA_BIN" -jar "$WEB_JAR"
  )
  exit $?
```

- [ ] **Step 7: Smoke-test the CLI iOS path**

Ensure `~/.testpilot/ios/` and `~/.testpilot/harness/` are present (from Task 2):
```bash
ls ~/.testpilot/ios/TestPilotShared.xcframework
ls ~/.testpilot/harness/Harness.xcodeproj
```

Then run a real iOS analyze (requires a booted simulator with an app):
```bash
./testpilot analyze \
  --platform ios \
  --app "Safari" \
  --objective "look at the home screen" \
  --provider anthropic \
  --api-key "$TESTPILOT_API_KEY" \
  --max-steps 1
```

Expected: starts xcodebuild, no "SDK build" step, outputs `TESTPILOT_STEP:` lines, produces a report.

- [ ] **Step 8: Commit**

```bash
git add testpilot
git commit -m "feat(cli): use pre-built artifacts via _ensure_artifact, remove Gradle from normal flow"
```

---

### Task 10: CI release workflow

**Files:**
- Create: `.github/workflows/release.yml`

Builds and publishes the four release artifacts (XCFramework zip, web runner tarball, manifest.json) and the signed+notarized Mac app DMG on every `v*` tag push.

**Prerequisites (one-time CI secrets setup):**
- `APPLE_DEVELOPER_ID_CERTIFICATE_P12` — base64-encoded Developer ID Application certificate
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` — certificate password
- `APPLE_TEAM_ID` — Apple Developer Team ID (e.g. `ABC123DEF4`)
- `APPLE_ASC_API_KEY_ID` — App Store Connect API key ID (for notarytool)
- `APPLE_ASC_API_KEY_ISSUER` — API key issuer ID
- `APPLE_ASC_API_KEY_P8` — base64-encoded .p8 key file

- [ ] **Step 1: Create .github/workflows/release.yml**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write   # required to create GitHub release

jobs:
  # ── Build iOS XCFramework + harness ──────────────────────────────────────────
  build-ios:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Build XCFramework
        run: scripts/build_ios_sdk.sh

      - name: Package ios artifact (framework + harness skeleton)
        run: |
          mkdir -p dist/ios
          cp -R sdk/testpilot/build/XCFrameworks/debug/TestPilotShared.xcframework dist/ios/
          rsync -a --exclude="AnalystTests/AnalystTests.swift" harness/ dist/harness/
          cd dist
          zip -qr TestPilotShared.xcframework.zip ios/ harness/
          echo "SHA256_IOS=$(shasum -a 256 TestPilotShared.xcframework.zip | awk '{print $1}')" >> $GITHUB_ENV
          mv TestPilotShared.xcframework.zip ../

      - uses: actions/upload-artifact@v4
        with:
          name: ios-artifact
          path: TestPilotShared.xcframework.zip

  # ── Build Web fat-jar + jlink JRE ────────────────────────────────────────────
  build-web:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'

      - name: Generate .def files (needed for KMP compilation)
        run: |
          export XCODE_PATH="/Applications/Xcode.app/Contents/Developer"
          export XCTEST_STUB_HEADER="$(pwd)/sdk/testpilot/src/iosMain/xctest_stub.h"
          for f in xctest_iosArm64 xctest_iosSimulatorArm64 xctest_iosX64; do
            envsubst < "sdk/testpilot/src/iosMain/$f.templ" > "sdk/testpilot/src/iosMain/$f.def"
          done
        # Note: iOS compilation is skipped on Linux; .def files just need to exist.

      - name: Build fat-jar
        run: |
          cd sdk
          ./gradlew testpilot:shadowJar

      - name: Create jlink JRE
        run: |
          JAR=sdk/testpilot/build/libs/testpilot-web.jar
          # Determine required modules (ignore missing for reflection-heavy libs)
          MODULES=$(jdeps --multi-release 21 \
            --ignore-missing-deps \
            --print-module-deps \
            "$JAR" 2>/dev/null || echo "")
          # Always include these modules needed by Ktor, Playwright, and Kotlin
          REQUIRED="java.base,java.net.http,java.sql,java.desktop,java.logging,java.management,java.naming,java.xml,jdk.crypto.ec,jdk.unsupported"
          COMBINED="${MODULES:+$MODULES,}$REQUIRED"
          # Deduplicate
          FINAL=$(echo "$COMBINED" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
          jlink --no-header-files --no-man-pages --compress=2 \
            --add-modules "$FINAL" \
            --output testpilot-jre

      - name: Package web artifact
        run: |
          mkdir -p dist/web
          cp sdk/testpilot/build/libs/testpilot-web.jar dist/web/
          cp -R testpilot-jre dist/web/jre
          tar -czf testpilot-web-runner.tar.gz -C dist web/
          echo "SHA256_WEB=$(sha256sum testpilot-web-runner.tar.gz | awk '{print $1}')" >> $GITHUB_ENV

      - uses: actions/upload-artifact@v4
        with:
          name: web-artifact
          path: testpilot-web-runner.tar.gz

  # ── Build, sign, and notarize Mac app DMG ────────────────────────────────────
  build-mac-app:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Import signing certificate
        env:
          CERT_P12: ${{ secrets.APPLE_DEVELOPER_ID_CERTIFICATE_P12 }}
          CERT_PASSWORD: ${{ secrets.APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/signing.keychain
          security create-keychain -p "" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "" "$KEYCHAIN_PATH"
          echo "$CERT_P12" | base64 --decode > /tmp/cert.p12
          security import /tmp/cert.p12 -k "$KEYCHAIN_PATH" \
            -P "$CERT_PASSWORD" -T /usr/bin/codesign
          security list-keychain -d user -s "$KEYCHAIN_PATH"

      - name: Build and archive Mac app
        env:
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcodebuild archive \
            -project mac-app/TestPilotApp.xcodeproj \
            -scheme TestPilotApp \
            -configuration Release \
            -destination "generic/platform=macOS" \
            -archivePath /tmp/TestPilot.xcarchive \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="$TEAM_ID"

      - name: Export app
        run: |
          cat > /tmp/export.plist <<EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>method</key><string>developer-id</string>
            <key>signingStyle</key><string>manual</string>
            <key>teamID</key><string>${{ secrets.APPLE_TEAM_ID }}</string>
          </dict>
          </plist>
          EOF
          xcodebuild -exportArchive \
            -archivePath /tmp/TestPilot.xcarchive \
            -exportPath /tmp/TestPilotExport \
            -exportOptionsPlist /tmp/export.plist

      - name: Create DMG
        run: |
          hdiutil create -volname "TestPilot" -srcfolder /tmp/TestPilotExport/TestPilot.app \
            -ov -format UDZO /tmp/TestPilot.dmg

      - name: Notarize DMG
        env:
          ASC_API_KEY_ID: ${{ secrets.APPLE_ASC_API_KEY_ID }}
          ASC_API_KEY_ISSUER: ${{ secrets.APPLE_ASC_API_KEY_ISSUER }}
          ASC_API_KEY_P8: ${{ secrets.APPLE_ASC_API_KEY_P8 }}
        run: |
          echo "$ASC_API_KEY_P8" | base64 --decode > /tmp/asc_key.p8
          xcrun notarytool submit /tmp/TestPilot.dmg \
            --key /tmp/asc_key.p8 \
            --key-id "$ASC_API_KEY_ID" \
            --issuer "$ASC_API_KEY_ISSUER" \
            --wait
          xcrun stapler staple /tmp/TestPilot.dmg

      - uses: actions/upload-artifact@v4
        with:
          name: mac-dmg
          path: /tmp/TestPilot.dmg

  # ── Create GitHub release with all artifacts ─────────────────────────────────
  create-release:
    runs-on: ubuntu-latest
    needs: [build-ios, build-web, build-mac-app]
    steps:
      - uses: actions/download-artifact@v4
        with:
          merge-multiple: true

      - name: Compute SHA256s
        run: |
          echo "SHA256_IOS=$(sha256sum TestPilotShared.xcframework.zip | awk '{print $1}')" >> $GITHUB_ENV
          echo "SHA256_WEB=$(sha256sum testpilot-web-runner.tar.gz | awk '{print $1}')" >> $GITHUB_ENV

      - name: Generate manifest.json
        run: |
          TAG="${GITHUB_REF_NAME}"
          BASE="https://github.com/${{ github.repository }}/releases/download/$TAG"
          cat > artifacts-manifest.json <<EOF
          {
            "version": "$TAG",
            "artifacts": {
              "ios": {
                "sha256": "$SHA256_IOS",
                "url": "$BASE/TestPilotShared.xcframework.zip"
              },
              "web": {
                "sha256": "$SHA256_WEB",
                "url": "$BASE/testpilot-web-runner.tar.gz"
              }
            }
          }
          EOF

      - name: Create GitHub release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            TestPilotShared.xcframework.zip
            testpilot-web-runner.tar.gz
            TestPilot.dmg
            artifacts-manifest.json
          generate_release_notes: true
```

- [ ] **Step 2: Commit the workflow**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow — build XCFramework, web runner, Mac app DMG"
```

- [ ] **Step 3: Tag a test release and verify**

Push a test tag and watch the Actions run:

```bash
git tag v0.1.0-test
git push origin v0.1.0-test
```

Check GitHub Actions: all four jobs should complete. Verify the release has four files:
- `TestPilotShared.xcframework.zip`
- `testpilot-web-runner.tar.gz`
- `TestPilot.dmg`
- `artifacts-manifest.json`

Download `artifacts-manifest.json` and verify SHA256s match the actual zips:
```bash
curl -fsSL "https://github.com/workco/testpilot/releases/download/v0.1.0-test/artifacts-manifest.json" | python3 -m json.tool
```

- [ ] **Step 4: Test ArtifactManager downloads from the release**

Delete local artifacts and launch the Mac app:
```bash
rm -rf ~/.testpilot/ios ~/.testpilot/web
```

Launch `TestPilot.app` — the setup sheet should appear, download both artifacts, and dismiss. After dismissal, verify:
```bash
ls ~/.testpilot/ios/TestPilotShared.xcframework
ls ~/.testpilot/web/testpilot-web.jar
ls ~/.testpilot/web/jre/bin/java
```

- [ ] **Step 5: Delete the test tag**

```bash
git push origin --delete v0.1.0-test
git tag -d v0.1.0-test
```
