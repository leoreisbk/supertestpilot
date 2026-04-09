# TestPilot macOS GUI App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI window app that wraps the `testpilot analyze` CLI with a device picker, animated running state, history, and settings.

**Architecture:** A single-window `NavigationSplitView` app with sidebar navigation (New Analysis, History, Settings). The Run form transitions in-place to a robot animation while the bundled `testpilot` bash script runs as a `Foundation.Process`. All AI credentials are injected as env vars at runtime; settings also persist to `~/.testpilot/.env` for CLI compatibility.

**Tech Stack:** SwiftUI + Observation framework (`@Observable`), macOS 14.0+, Xcode project generated via `xcodegen`, Foundation.Process for subprocess, Security framework for Keychain.

---

## File Map

```
mac-app/
  project.yml                              # xcodegen manifest
  TestPilot.xcodeproj/                     # generated — never edit by hand
  TestPilotApp/
    App.swift                              # @main, WindowGroup, min size
    Info.plist                             # bundle metadata
    Views/
      ContentView.swift                    # NavigationSplitView root + state router
      RunView.swift                        # Analysis form
      RunningView.swift                    # Animation + completion/error state
      SettingsView.swift                   # Provider/key/teamid + raw .env editor
      HistoryView.swift                    # Recent runs list
    Models/
      RunConfig.swift                      # @Observable form state + isValid
      DeviceInfo.swift                     # Device value type (id, name, DeviceType)
      RunRecord.swift                      # Codable history entry
    Services/
      DeviceDetector.swift                 # @Observable; queries xcrun simctl + devicectl + adb
      AnalysisRunner.swift                 # @Observable; launches Process, reads stdout
      SettingsStore.swift                  # @Observable; Keychain + UserDefaults + .env file
      HistoryStore.swift                   # @Observable; JSON array in App Support
    Animations/
      RobotAnimationView.swift             # TimelineView + Canvas robot animation
  TestPilotTests/
    HistoryStoreTests.swift
    SettingsStoreTests.swift
    RunConfigTests.swift
```

---

## Task 1: Scaffold Xcode project with xcodegen

**Files:**
- Create: `mac-app/project.yml`
- Create: `mac-app/TestPilotApp/Info.plist`
- Generate: `mac-app/TestPilot.xcodeproj/` (via xcodegen)

- [ ] **Step 1: Install xcodegen if not present**

```bash
which xcodegen || brew install xcodegen
```

Expected: prints a path or installs successfully.

- [ ] **Step 2: Create mac-app directory**

```bash
mkdir -p /path/to/repo/mac-app/TestPilotApp/Views \
         /path/to/repo/mac-app/TestPilotApp/Models \
         /path/to/repo/mac-app/TestPilotApp/Services \
         /path/to/repo/mac-app/TestPilotApp/Animations \
         /path/to/repo/mac-app/TestPilotTests
```

- [ ] **Step 3: Write project.yml**

Create `mac-app/project.yml`:

```yaml
name: TestPilot
options:
  bundleIdPrefix: com.workco
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15"
fileGroups:
  - project.yml
targets:
  TestPilotApp:
    type: application
    platform: macOS
    sources:
      - TestPilotApp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.workco.testpilot
        SWIFT_VERSION: 5.9
        INFOPLIST_FILE: TestPilotApp/Info.plist
        CODE_SIGN_STYLE: Automatic
        ENABLE_APP_SANDBOX: NO
    postBuildScripts:
      - name: Copy and chmod testpilot script
        script: |
          SCRIPT_SRC="${SRCROOT}/../testpilot"
          DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/testpilot"
          mkdir -p "$(dirname "$DEST")"
          cp "$SCRIPT_SRC" "$DEST"
          chmod +x "$DEST"
        outputFiles:
          - $(BUILT_PRODUCTS_DIR)/$(CONTENTS_FOLDER_PATH)/Resources/testpilot
  TestPilotTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - TestPilotTests
    dependencies:
      - target: TestPilotApp
    settings:
      base:
        SWIFT_VERSION: 5.9
```

- [ ] **Step 4: Write Info.plist**

Create `mac-app/TestPilotApp/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TestPilot</string>
    <key>CFBundleDisplayName</key>
    <string>TestPilot</string>
    <key>CFBundleIdentifier</key>
    <string>com.workco.testpilot</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Generate the Xcode project**

```bash
cd mac-app && xcodegen generate
```

Expected: `Generating project TestPilot` followed by `Created project at mac-app/TestPilot.xcodeproj`.

- [ ] **Step 6: Add .gitignore for build artifacts**

Add to (or create) `mac-app/.gitignore`:

```
xcuserdata/
*.xcuserstate
DerivedData/
```

- [ ] **Step 7: Verify the project opens and compiles (empty)**

```bash
cd mac-app && xcodebuild -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` (will fail once we add Swift files — that's expected at this stage, just confirm the project file is valid).

- [ ] **Step 8: Commit scaffold**

```bash
git add mac-app/project.yml mac-app/TestPilotApp/Info.plist mac-app/.gitignore mac-app/TestPilot.xcodeproj
git commit -m "feat(mac-app): scaffold Xcode project via xcodegen"
```

---

## Task 2: Models — RunConfig, DeviceInfo, RunRecord

**Files:**
- Create: `mac-app/TestPilotApp/Models/RunConfig.swift`
- Create: `mac-app/TestPilotApp/Models/DeviceInfo.swift`
- Create: `mac-app/TestPilotApp/Models/RunRecord.swift`
- Create: `mac-app/TestPilotTests/RunConfigTests.swift`

- [ ] **Step 1: Write RunConfigTests.swift (failing)**

Create `mac-app/TestPilotTests/RunConfigTests.swift`:

```swift
import XCTest
@testable import TestPilotApp

final class RunConfigTests: XCTestCase {
    func testIsValidRequiresDeviceAppAndObjective() {
        let config = RunConfig()
        XCTAssertFalse(config.isValid, "empty config should be invalid")

        config.appName = "Pharmia"
        config.objective = "Check onboarding"
        XCTAssertFalse(config.isValid, "missing device should be invalid")

        config.selectedDevice = DeviceInfo(id: "abc", name: "iPhone 15", type: .simulator)
        XCTAssertTrue(config.isValid, "all required fields filled should be valid")
    }

    func testIsValidRejectsWhitespaceOnly() {
        let config = RunConfig()
        config.selectedDevice = DeviceInfo(id: "abc", name: "iPhone 15", type: .simulator)
        config.appName = "   "
        config.objective = "   "
        XCTAssertFalse(config.isValid, "whitespace-only fields should be invalid")
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: compile error — `RunConfig` and `DeviceInfo` not defined.

- [ ] **Step 3: Write DeviceInfo.swift**

Create `mac-app/TestPilotApp/Models/DeviceInfo.swift`:

```swift
import Foundation

enum DeviceType {
    case simulator, physical, androidEmulator, androidDevice
}

struct DeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let type: DeviceType

    var isPhysical: Bool {
        type == .physical || type == .androidDevice
    }

    var displayName: String {
        switch type {
        case .simulator:       return "\(name) (Simulator)"
        case .physical:        return "\(name) (Device)"
        case .androidEmulator: return "\(name) (Emulator)"
        case .androidDevice:   return "\(name) (Device)"
        }
    }
}
```

- [ ] **Step 4: Write RunConfig.swift**

Create `mac-app/TestPilotApp/Models/RunConfig.swift`:

```swift
import Observation

enum Platform: String, CaseIterable, Identifiable {
    case ios = "ios"
    case android = "android"
    var id: String { rawValue }
    var displayName: String { self == .ios ? "iOS" : "Android" }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic, openai, gemini
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Language: String, CaseIterable, Identifiable {
    case en
    case ptBR = "pt-BR"
    var id: String { rawValue }
    var displayName: String { self == .en ? "English" : "Português (BR)" }
}

@Observable
final class RunConfig {
    var platform: Platform = .ios
    var selectedDevice: DeviceInfo? = nil
    var appName: String = ""
    var objective: String = ""
    var language: Language = .en
    var maxSteps: Int = 20
    var outputPath: String = "~/Desktop/report.html"
    var providerOverride: AIProvider? = nil

    var isValid: Bool {
        selectedDevice != nil
            && !appName.trimmingCharacters(in: .whitespaces).isEmpty
            && !objective.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
```

- [ ] **Step 5: Write RunRecord.swift**

Create `mac-app/TestPilotApp/Models/RunRecord.swift`:

```swift
import Foundation

struct RunRecord: Codable, Identifiable {
    let id: UUID
    let appName: String
    let platform: String
    let objective: String
    let reportPath: String
    let date: Date

    init(appName: String, platform: String, objective: String, reportPath: String) {
        self.id = UUID()
        self.appName = appName
        self.platform = platform
        self.objective = objective
        self.reportPath = reportPath
        self.date = Date()
    }
}
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|FAILED|SUCCEEDED"
```

Expected: `RunConfigTests` — 2 tests passed.

- [ ] **Step 7: Commit**

```bash
git add mac-app/TestPilotApp/Models/ mac-app/TestPilotTests/RunConfigTests.swift
git commit -m "feat(mac-app): add RunConfig, DeviceInfo, RunRecord models"
```

---

## Task 3: HistoryStore + tests

**Files:**
- Create: `mac-app/TestPilotApp/Services/HistoryStore.swift`
- Create: `mac-app/TestPilotTests/HistoryStoreTests.swift`

- [ ] **Step 1: Write HistoryStoreTests.swift (failing)**

Create `mac-app/TestPilotTests/HistoryStoreTests.swift`:

```swift
import XCTest
@testable import TestPilotApp

final class HistoryStoreTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testAppendAddsRecord() {
        let store = HistoryStore(fileURL: tempURL)
        let record = RunRecord(appName: "Pharmia", platform: "ios",
                               objective: "Check flow", reportPath: "/tmp/r.html")
        store.append(record)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[0].appName, "Pharmia")
    }

    func testNewestRecordIsFirst() {
        let store = HistoryStore(fileURL: tempURL)
        store.append(RunRecord(appName: "First", platform: "ios", objective: "o", reportPath: "/r"))
        store.append(RunRecord(appName: "Second", platform: "ios", objective: "o", reportPath: "/r"))
        XCTAssertEqual(store.records[0].appName, "Second")
    }

    func testMaxEntriesEnforced() {
        let store = HistoryStore(fileURL: tempURL, maxEntries: 3)
        for i in 0..<5 {
            store.append(RunRecord(appName: "App\(i)", platform: "ios",
                                   objective: "o", reportPath: "/r"))
        }
        XCTAssertEqual(store.records.count, 3)
    }

    func testPersistsAcrossInstances() {
        let store1 = HistoryStore(fileURL: tempURL)
        store1.append(RunRecord(appName: "Saved", platform: "ios",
                                objective: "o", reportPath: "/r"))

        let store2 = HistoryStore(fileURL: tempURL)
        XCTAssertEqual(store2.records.count, 1)
        XCTAssertEqual(store2.records[0].appName, "Saved")
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED"
```

Expected: compile error — `HistoryStore` not defined.

- [ ] **Step 3: Write HistoryStore.swift**

Create `mac-app/TestPilotApp/Services/HistoryStore.swift`:

```swift
import Foundation
import Observation

@Observable
final class HistoryStore {
    private(set) var records: [RunRecord] = []
    private let maxEntries: Int
    private let fileURL: URL

    init(
        fileURL: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TestPilot/history.json"),
        maxEntries: Int = 50
    ) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        load()
    }

    func append(_ record: RunRecord) {
        records.insert(record, at: 0)
        if records.count > maxEntries {
            records = Array(records.prefix(maxEntries))
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RunRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|SUCCEEDED"
```

Expected: 4 `HistoryStoreTests` tests passed.

- [ ] **Step 5: Commit**

```bash
git add mac-app/TestPilotApp/Services/HistoryStore.swift mac-app/TestPilotTests/HistoryStoreTests.swift
git commit -m "feat(mac-app): add HistoryStore with JSON persistence"
```

---

## Task 4: SettingsStore + tests

**Files:**
- Create: `mac-app/TestPilotApp/Services/SettingsStore.swift`
- Create: `mac-app/TestPilotTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write SettingsStoreTests.swift (failing)**

Create `mac-app/TestPilotTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import TestPilotApp

final class SettingsStoreTests: XCTestCase {
    func testParseEnvStringExtractsProvider() {
        let raw = "TESTPILOT_PROVIDER=gemini\nTESTPILOT_TEAM_ID=ABC123"
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.provider, .gemini)
        XCTAssertEqual(parsed.teamId, "ABC123")
        XCTAssertNil(parsed.apiKey)
    }

    func testParseEnvStringExtractsApiKey() {
        let raw = "TESTPILOT_API_KEY=sk-test\nTESTPILOT_PROVIDER=openai"
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.apiKey, "sk-test")
        XCTAssertEqual(parsed.provider, .openai)
    }

    func testBuildEnvStringRoundTrip() {
        let raw = SettingsStore.buildEnv(apiKey: "my-key", provider: .anthropic, teamId: "T99")
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.apiKey, "my-key")
        XCTAssertEqual(parsed.provider, .anthropic)
        XCTAssertEqual(parsed.teamId, "T99")
    }

    func testParseEnvIgnoresUnknownKeys() {
        let raw = "SOME_OTHER_VAR=foo\nTESTPILOT_PROVIDER=anthropic"
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.provider, .anthropic)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED"
```

Expected: compile error — `SettingsStore` not defined.

- [ ] **Step 3: Write SettingsStore.swift**

Create `mac-app/TestPilotApp/Services/SettingsStore.swift`:

```swift
import Foundation
import Security
import Observation

@Observable
final class SettingsStore {
    var provider: AIProvider = .anthropic
    var teamId: String = ""

    private let keychainService = "com.workco.testpilot"
    private let keychainAccount = "api-key"
    private let providerKey = "tp_provider"
    private let teamIdKey = "tp_teamId"

    private var envFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot/.env")
    }

    // MARK: - API Key (Keychain)

    var apiKey: String {
        get { keychainLoad() ?? "" }
        set { keychainSave(newValue) }
    }

    // MARK: - Raw .env (bidirectional sync)

    var rawEnv: String {
        get { SettingsStore.buildEnv(apiKey: apiKey, provider: provider, teamId: teamId) }
        set {
            let parsed = SettingsStore.parseEnv(newValue)
            if let k = parsed.apiKey { apiKey = k }
            if let p = parsed.provider { provider = p }
            if let t = parsed.teamId { teamId = t }
        }
    }

    // MARK: - Init

    init() {
        provider = {
            guard let raw = UserDefaults.standard.string(forKey: "tp_provider"),
                  let p = AIProvider(rawValue: raw) else { return .anthropic }
            return p
        }()
        teamId = UserDefaults.standard.string(forKey: "tp_teamId") ?? ""
        // Bootstrap from .env if it exists and we have no saved provider yet
        if let contents = try? String(contentsOf: envFileURL) {
            let parsed = SettingsStore.parseEnv(contents)
            if let k = parsed.apiKey, apiKey.isEmpty { apiKey = k }
            if let p = parsed.provider { provider = p }
            if let t = parsed.teamId, teamId.isEmpty { teamId = t }
        }
    }

    // MARK: - Persist

    func save() {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
        UserDefaults.standard.set(teamId, forKey: teamIdKey)
        writeEnvFile()
    }

    private func writeEnvFile() {
        let dir = envFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? rawEnv.write(to: envFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Static helpers (testable)

    struct ParsedEnv {
        var apiKey: String?
        var provider: AIProvider?
        var teamId: String?
    }

    static func parseEnv(_ raw: String) -> ParsedEnv {
        var result = ParsedEnv()
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "TESTPILOT_API_KEY":  result.apiKey = value
            case "TESTPILOT_PROVIDER": result.provider = AIProvider(rawValue: value)
            case "TESTPILOT_TEAM_ID":  result.teamId = value
            default: break
            }
        }
        return result
    }

    static func buildEnv(apiKey: String, provider: AIProvider, teamId: String) -> String {
        var lines: [String] = []
        if !apiKey.isEmpty  { lines.append("TESTPILOT_API_KEY=\(apiKey)") }
        lines.append("TESTPILOT_PROVIDER=\(provider.rawValue)")
        if !teamId.isEmpty  { lines.append("TESTPILOT_TEAM_ID=\(teamId)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Keychain

    private func keychainLoad() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainSave(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|SUCCEEDED"
```

Expected: 4 `SettingsStoreTests` tests passed, plus all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add mac-app/TestPilotApp/Services/SettingsStore.swift mac-app/TestPilotTests/SettingsStoreTests.swift
git commit -m "feat(mac-app): add SettingsStore with Keychain and .env sync"
```

---

## Task 5: DeviceDetector

**Files:**
- Create: `mac-app/TestPilotApp/Services/DeviceDetector.swift`

No unit tests — device detection requires live system tools (`xcrun`, `adb`). Manual verification in Task 9 (RunView smoke test).

- [ ] **Step 1: Write DeviceDetector.swift**

Create `mac-app/TestPilotApp/Services/DeviceDetector.swift`:

```swift
import Foundation
import Observation

@Observable
final class DeviceDetector {
    private(set) var devices: [DeviceInfo] = []
    private(set) var isRefreshing = false

    func refresh(for platform: Platform) async {
        await MainActor.run { isRefreshing = true }
        let found: [DeviceInfo]
        switch platform {
        case .ios:     found = await fetchIOSDevices()
        case .android: found = await fetchAndroidDevices()
        }
        await MainActor.run {
            devices = found
            isRefreshing = false
        }
    }

    // MARK: - iOS

    private func fetchIOSDevices() async -> [DeviceInfo] {
        async let simulators = fetchBootedSimulators()
        async let physical   = fetchPhysicalDevices()
        return await simulators + physical
    }

    private func fetchBootedSimulators() async -> [DeviceInfo] {
        guard let output = await shell("/usr/bin/xcrun",
                                       args: ["simctl", "list", "devices", "--json"]),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        return devicesMap.values.flatMap { list in
            list.compactMap { d -> DeviceInfo? in
                guard let state = d["state"] as? String, state == "Booted",
                      let udid = d["udid"] as? String,
                      let name = d["name"] as? String
                else { return nil }
                return DeviceInfo(id: udid, name: name, type: .simulator)
            }
        }
    }

    private func fetchPhysicalDevices() async -> [DeviceInfo] {
        // devicectl outputs JSON to a temp file
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard (await shell("/usr/bin/xcrun",
                           args: ["devicectl", "list", "devices",
                                  "--json-output", tmp.path])) != nil,
              let data = try? Data(contentsOf: tmp),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let list = result["devices"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { d -> DeviceInfo? in
            guard let udid = d["identifier"] as? String,
                  let props = d["deviceProperties"] as? [String: Any],
                  let name = props["name"] as? String
            else { return nil }
            return DeviceInfo(id: udid, name: name, type: .physical)
        }
    }

    // MARK: - Android

    private func fetchAndroidDevices() async -> [DeviceInfo] {
        guard let output = await shell("/usr/bin/env", args: ["adb", "devices"]) else { return [] }
        return output
            .split(separator: "\n")
            .dropFirst() // skip "List of devices attached"
            .compactMap { line -> DeviceInfo? in
                let parts = line.split(separator: "\t")
                guard parts.count == 2 else { return nil }
                let serial = String(parts[0])
                let status = String(parts[1]).trimmingCharacters(in: .whitespaces)
                guard status == "device" else { return nil }
                let type: DeviceType = serial.hasPrefix("emulator-") ? .androidEmulator : .androidDevice
                return DeviceInfo(id: serial, name: serial, type: type)
            }
    }

    // MARK: - Shell helper

    private func shell(_ executable: String, args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Services/DeviceDetector.swift
git commit -m "feat(mac-app): add DeviceDetector for simulators, physical, and adb"
```

---

## Task 6: AnalysisRunner

**Files:**
- Create: `mac-app/TestPilotApp/Services/AnalysisRunner.swift`

- [ ] **Step 1: Write AnalysisRunner.swift**

Create `mac-app/TestPilotApp/Services/AnalysisRunner.swift`:

```swift
import Foundation
import AppKit
import Observation

enum AnalysisState: Equatable {
    case idle
    case running(statusLine: String)
    case completed(reportPath: String)
    case failed(error: String)
}

@Observable
final class AnalysisRunner {
    private(set) var state: AnalysisState = .idle
    private var process: Process?

    func run(config: RunConfig, settings: SettingsStore) {
        guard let scriptURL = Bundle.main.url(forResource: "testpilot", withExtension: nil) else {
            state = .failed(error: "testpilot script not found in app bundle")
            return
        }

        let outputPath = NSString(string: config.outputPath).expandingTildeInPath

        var args: [String] = [
            "analyze",
            "--platform", config.platform.rawValue,
            "--app",      config.appName,
            "--objective", config.objective,
            "--lang",     config.language.rawValue,
            "--max-steps", "\(config.maxSteps)",
            "--output",   outputPath
        ]

        if let device = config.selectedDevice, device.isPhysical {
            args += ["--device", device.id]
            if !settings.teamId.isEmpty {
                args += ["--team-id", settings.teamId]
            }
        }

        let provider = config.providerOverride ?? settings.provider
        args += ["--provider", provider.rawValue]

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_API_KEY"]  = settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider.rawValue
        if !settings.teamId.isEmpty {
            env["TESTPILOT_TEAM_ID"] = settings.teamId
        }

        let p = Process()
        p.executableURL = scriptURL
        p.arguments = args
        p.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError  = stderr

        var lastStderr = ""

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty
            else { return }
            DispatchQueue.main.async { self?.state = .running(statusLine: line) }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            if let s = String(data: handle.availableData, encoding: .utf8), !s.isEmpty {
                lastStderr = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        p.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    self?.state = .completed(reportPath: outputPath)
                } else {
                    let msg = lastStderr.isEmpty
                        ? "Analysis failed (exit \(proc.terminationStatus))"
                        : lastStderr
                    self?.state = .failed(error: msg)
                }
            }
        }

        state = .running(statusLine: "Starting analysis…")
        process = p

        do {
            try p.run()
        } catch {
            state = .failed(error: error.localizedDescription)
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .idle
    }

    func reset() {
        state = .idle
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Services/AnalysisRunner.swift
git commit -m "feat(mac-app): add AnalysisRunner with Process launch and stdout streaming"
```

---

## Task 7: RobotAnimationView

**Files:**
- Create: `mac-app/TestPilotApp/Animations/RobotAnimationView.swift`

- [ ] **Step 1: Write RobotAnimationView.swift**

Create `mac-app/TestPilotApp/Animations/RobotAnimationView.swift`:

```swift
import SwiftUI

struct RobotAnimationView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2

                // Body
                let body = CGRect(x: cx - 35, y: cy - 20, width: 70, height: 55)
                context.fill(Path(roundedRect: body, cornerRadius: 10),
                             with: .color(.blue.opacity(0.85)))

                // Head
                let head = CGRect(x: cx - 25, y: cy - 68, width: 50, height: 48)
                context.fill(Path(roundedRect: head, cornerRadius: 8),
                             with: .color(.blue.opacity(0.9)))

                // Eyes (blink)
                let blink = sin(t * 1.8) > 0.93 ? 2.0 : 9.0
                context.fill(Path(ellipseIn: CGRect(x: cx - 17, y: cy - 58, width: 11, height: blink)),
                             with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: cx + 6,  y: cy - 58, width: 11, height: blink)),
                             with: .color(.white))

                // Antenna
                var antenna = Path()
                antenna.move(to: CGPoint(x: cx, y: cy - 68))
                antenna.addLine(to: CGPoint(x: cx, y: cy - 84))
                context.stroke(antenna, with: .color(.blue.opacity(0.9)), lineWidth: 3)
                let glow = (sin(t * 3.2) + 1) / 2
                context.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 91, width: 10, height: 10)),
                             with: .color(.cyan.opacity(0.5 + glow * 0.5)))

                // Left arm (holding phone) — slight swing
                let swing = sin(t * 1.4) * 4
                var leftArm = Path()
                leftArm.move(to: CGPoint(x: cx - 35, y: cy - 8))
                leftArm.addLine(to: CGPoint(x: cx - 62, y: cy + 14 + swing))
                context.stroke(leftArm, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                // Phone in left hand
                let phone = CGRect(x: cx - 82, y: cy + 9 + swing, width: 24, height: 38)
                context.fill(Path(roundedRect: phone, cornerRadius: 4),
                             with: .color(Color(white: 0.25)))
                let screenGlow = (sin(t * 4.5) + 1) / 2
                let screen = CGRect(x: cx - 80, y: cy + 13 + swing, width: 20, height: 26)
                context.fill(Path(roundedRect: screen, cornerRadius: 2),
                             with: .color(.cyan.opacity(0.25 + screenGlow * 0.75)))

                // Right arm
                var rightArm = Path()
                rightArm.move(to: CGPoint(x: cx + 35, y: cy - 8))
                rightArm.addLine(to: CGPoint(x: cx + 55, y: cy + 5 - swing))
                context.stroke(rightArm, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                // Legs
                var leftLeg = Path()
                leftLeg.move(to: CGPoint(x: cx - 14, y: cy + 35))
                leftLeg.addLine(to: CGPoint(x: cx - 17, y: cy + 62))
                context.stroke(leftLeg, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                var rightLeg = Path()
                rightLeg.move(to: CGPoint(x: cx + 14, y: cy + 35))
                rightLeg.addLine(to: CGPoint(x: cx + 17, y: cy + 62))
                context.stroke(rightLeg, with: .color(.blue.opacity(0.85)), lineWidth: 9)

                // Thinking dots above head
                for i in 0..<3 {
                    let phase = sin(t * 2.8 + Double(i) * 0.9)
                    let alpha = (phase + 1) / 2
                    let dotY = cy - 104 - phase * 4
                    let dot = CGRect(x: cx - 9 + Double(i) * 9, y: dotY, width: 7, height: 7)
                    context.fill(Path(ellipseIn: dot), with: .color(.cyan.opacity(alpha)))
                }
            }
        }
        .frame(width: 200, height: 200)
    }
}

#Preview {
    RobotAnimationView()
        .frame(width: 300, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
```

- [ ] **Step 2: Build to confirm no errors**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Animations/RobotAnimationView.swift
git commit -m "feat(mac-app): add RobotAnimationView with TimelineView canvas animation"
```

---

## Task 8: App.swift + ContentView

**Files:**
- Create: `mac-app/TestPilotApp/App.swift`
- Create: `mac-app/TestPilotApp/Views/ContentView.swift`

- [ ] **Step 1: Write App.swift**

Create `mac-app/TestPilotApp/App.swift`:

```swift
import SwiftUI

@main
struct TestPilotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 760, height: 540)
        .windowResizability(.contentMinSize)
    }
}
```

- [ ] **Step 2: Write ContentView.swift**

Create `mac-app/TestPilotApp/Views/ContentView.swift`:

```swift
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case newAnalysis = "New Analysis"
    case history     = "History"
    case settings    = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .newAnalysis: return "plus.circle"
        case .history:     return "clock"
        case .settings:    return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .newAnalysis
    @State private var config   = RunConfig()
    @State private var runner   = AnalysisRunner()
    @State private var settings = SettingsStore()
    @State private var history  = HistoryStore()
    @State private var detector = DeviceDetector()

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
        .onChange(of: runner.state) { _, newState in
            if case .completed(let path) = newState {
                history.append(RunRecord(
                    appName:    config.appName,
                    platform:   config.platform.rawValue,
                    objective:  config.objective,
                    reportPath: path
                ))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .newAnalysis, .none:
            switch runner.state {
            case .idle:
                RunView(config: config, detector: detector,
                        settings: settings, runner: runner)
            default:
                RunningView(runner: runner, config: config)
            }
        case .history:
            HistoryView(store: history)
        case .settings:
            SettingsView(store: settings)
        }
    }
}
```

- [ ] **Step 3: Build (will fail — RunView etc. not yet written)**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep "error:"
```

Expected: errors for `RunView`, `RunningView`, `HistoryView`, `SettingsView` not found — that's correct, coming next.

- [ ] **Step 4: Commit**

```bash
git add mac-app/TestPilotApp/App.swift mac-app/TestPilotApp/Views/ContentView.swift
git commit -m "feat(mac-app): add App entry point and ContentView navigation shell"
```

---

## Task 9: RunView

**Files:**
- Create: `mac-app/TestPilotApp/Views/RunView.swift`

- [ ] **Step 1: Write RunView.swift**

Create `mac-app/TestPilotApp/Views/RunView.swift`:

```swift
import SwiftUI
import AppKit

struct RunView: View {
    @Bindable var config: RunConfig
    var detector: DeviceDetector
    var settings: SettingsStore
    var runner: AnalysisRunner

    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Required") {
                Picker("Platform", selection: $config.platform) {
                    ForEach(Platform.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: config.platform) { _, _ in
                    config.selectedDevice = nil
                    Task { await detector.refresh(for: config.platform) }
                }

                HStack {
                    Picker("Device", selection: $config.selectedDevice) {
                        Text("Select a device").tag(Optional<DeviceInfo>(nil))
                        ForEach(detector.devices) { device in
                            Text(device.displayName).tag(Optional(device))
                        }
                    }
                    if detector.isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button {
                            Task { await detector.refresh(for: config.platform) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh device list")
                    }
                }

                TextField("App name", text: $config.appName)

                ZStack(alignment: .topLeading) {
                    if config.objective.isEmpty {
                        Text("Describe what to analyze…")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $config.objective)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                }
            }

            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                Picker("Language", selection: $config.language) {
                    ForEach(Language.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }

                Stepper("Max steps: \(config.maxSteps)",
                        value: $config.maxSteps, in: 1...100)

                HStack {
                    TextField("Output path", text: $config.outputPath)
                    Button("Choose…") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.html]
                        panel.nameFieldStringValue = "report.html"
                        if panel.runModal() == .OK, let url = panel.url {
                            config.outputPath = url.path
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Provider", selection: $config.providerOverride) {
                    Text("From Settings (\(settings.provider.displayName))")
                        .tag(Optional<AIProvider>(nil))
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(Optional(p))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Button("Run Analysis") {
                runner.run(config: config, settings: settings)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding()
            .disabled(!config.isValid)
        }
        .task {
            await detector.refresh(for: config.platform)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await detector.refresh(for: config.platform) }
        }
        .navigationTitle("New Analysis")
    }
}
```

- [ ] **Step 2: Build (still missing RunningView, HistoryView, SettingsView)**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep "error:"
```

Expected: only errors for the three remaining views.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Views/RunView.swift
git commit -m "feat(mac-app): add RunView analysis form"
```

---

## Task 10: RunningView

**Files:**
- Create: `mac-app/TestPilotApp/Views/RunningView.swift`

- [ ] **Step 1: Write RunningView.swift**

Create `mac-app/TestPilotApp/Views/RunningView.swift`:

```swift
import SwiftUI
import AppKit

struct RunningView: View {
    var runner: AnalysisRunner
    var config: RunConfig

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 6) {
                Text(config.appName)
                    .font(.headline)
                Text(config.objective)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // State-driven content
            switch runner.state {
            case .running(let statusLine):
                RobotAnimationView()
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .animation(.easeInOut(duration: 0.3), value: statusLine)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)

            case .completed(let path):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                Text("Analysis complete")
                    .font(.title3.weight(.medium))
                HStack(spacing: 16) {
                    Button("Open Report") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Run Another") { runner.reset() }
                        .buttonStyle(.bordered)
                }

            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                Text("Analysis failed")
                    .font(.title3.weight(.medium))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Try Again") { runner.reset() }
                    .buttonStyle(.bordered)

            case .idle:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: runner.state)
    }
}
```

- [ ] **Step 2: Build (still missing HistoryView, SettingsView)**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep "error:"
```

Expected: only errors for `HistoryView` and `SettingsView`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Views/RunningView.swift
git commit -m "feat(mac-app): add RunningView with animation, completion, and error states"
```

---

## Task 11: SettingsView

**Files:**
- Create: `mac-app/TestPilotApp/Views/SettingsView.swift`

- [ ] **Step 1: Write SettingsView.swift**

Create `mac-app/TestPilotApp/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    @State private var apiKeyText  = ""
    @State private var rawEnvText  = ""
    @State private var showRawEnv  = false

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $store.provider) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .onChange(of: store.provider) { _, _ in store.save() }

                SecureField("API Key", text: $apiKeyText)
                    .onAppear { apiKeyText = store.apiKey }
                    .onChange(of: apiKeyText) { _, v in
                        store.apiKey = v
                        rawEnvText = store.rawEnv
                        store.save()
                    }

                TextField("Apple Team ID (physical iOS devices)", text: $store.teamId)
                    .onChange(of: store.teamId) { _, _ in
                        rawEnvText = store.rawEnv
                        store.save()
                    }
            }

            Section {
                DisclosureGroup("Raw .env  (~/.testpilot/.env)", isExpanded: $showRawEnv) {
                    TextEditor(text: $rawEnvText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .onChange(of: rawEnvText) { _, v in
                            store.rawEnv = v
                            store.save()
                            apiKeyText = store.apiKey   // sync back
                        }
                }
            } footer: {
                Text("Edits here sync with the fields above and are written to disk for use with the CLI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { rawEnvText = store.rawEnv }
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 2: Build (still missing HistoryView)**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep "error:"
```

Expected: only error for `HistoryView`.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Views/SettingsView.swift
git commit -m "feat(mac-app): add SettingsView with provider, API key, and .env editor"
```

---

## Task 12: HistoryView + full build verification

**Files:**
- Create: `mac-app/TestPilotApp/Views/HistoryView.swift`

- [ ] **Step 1: Write HistoryView.swift**

Create `mac-app/TestPilotApp/Views/HistoryView.swift`:

```swift
import SwiftUI
import AppKit

struct HistoryView: View {
    var store: HistoryStore

    var body: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "No analyses yet",
                    systemImage: "clock",
                    description: Text("Run an analysis to see it here.")
                )
            } else {
                List(store.records) { record in
                    HistoryRowView(record: record)
                }
            }
        }
        .navigationTitle("History")
    }
}

private struct HistoryRowView: View {
    let record: RunRecord
    @State private var reportMissing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.appName).fontWeight(.medium)
                    Text(record.platform.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(record.platform == "ios"
                                    ? Color.blue.opacity(0.15)
                                    : Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(record.objective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button("Open Report") {
                    let path = record.reportPath
                    if FileManager.default.fileExists(atPath: path) {
                        reportMissing = false
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } else {
                        reportMissing = true
                    }
                }
                .buttonStyle(.bordered)
                if reportMissing {
                    Text("File not found")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Full clean build**

```bash
cd mac-app && xcodebuild build -project TestPilot.xcodeproj -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run all tests**

```bash
cd mac-app && xcodebuild test -project TestPilot.xcodeproj -scheme TestPilotTests -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|SUCCEEDED|FAILED"
```

Expected: all tests pass (RunConfigTests ×2, HistoryStoreTests ×4, SettingsStoreTests ×4).

- [ ] **Step 4: Smoke test — run the app**

```bash
open mac-app/TestPilot.xcodeproj
```

In Xcode: press ⌘R to run. Verify:
- Window opens at ~760×540, sidebar shows New Analysis / History / Settings
- Platform picker defaults to iOS
- Device dropdown triggers `xcrun simctl` query; booted simulators appear
- Refresh button (↺) works
- App name + objective fields are required before Run button enables
- Settings view shows Provider / API Key / Team ID fields
- Raw .env disclosure group shows and edits the fields
- History view shows "No analyses yet" on first launch

- [ ] **Step 5: Commit**

```bash
git add mac-app/TestPilotApp/Views/HistoryView.swift
git commit -m "feat(mac-app): add HistoryView; full app builds and all tests pass"
```

---

## Post-Implementation Notes

- **testpilot script permissions:** The post-build script in `project.yml` runs `chmod +x` on the copied script. If the build script is sandboxed, you may need to set `ENABLE_HARDENED_RUNTIME = NO` in the target settings.
- **adb PATH:** Android device detection uses `/usr/bin/env adb`. If `adb` is not in the user's shell PATH when launched from Finder, it will silently return no devices. A future improvement is to let the user set the ADB path in Settings.
- **Xcode project regeneration:** After changing `project.yml`, run `cd mac-app && xcodegen generate` to regenerate. Do not hand-edit `TestPilot.xcodeproj`.
