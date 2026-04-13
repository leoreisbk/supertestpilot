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
    @MainActor
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
    @MainActor
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
    @MainActor
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

        // Pass credentials via test environment — they are read by the generated Swift at runtime
        // and never stored as string literals in the test file on disk.
        args += ["-testenv", "TESTPILOT_API_KEY=\(settings.apiKey)"]
        if !config.username.isEmpty {
            args += ["-testenv", "TESTPILOT_USERNAME=\(config.username)"]
        }
        if !config.password.isEmpty {
            args += ["-testenv", "TESTPILOT_PASSWORD=\(config.password)"]
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
        _ = try await runProcess(
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

    @MainActor
    private func buildTestSwift(bundleId: String) -> String {
        let provider = (config.providerOverride ?? settings.provider).rawValue
        let provEsc  = swiftEsc(provider)
        let objEsc   = swiftEsc(config.objective)
        let langEsc  = swiftEsc(config.language.rawValue)
        let bidOpt   = bundleId.isEmpty ? "nil" : "\"\(swiftEsc(bundleId))\""
        let xcAppInit = bundleId.isEmpty
            ? "XCUIApplication()"
            : "XCUIApplication(bundleIdentifier: \(bidOpt))"
        let maxSteps = config.maxSteps

        let providerExpr =
            "\"\(provEsc)\" == \"openai\" ? .openai : (\"\(provEsc)\" == \"gemini\" ? .gemini : .anthropic)"

        // Credentials are read from the test environment at runtime — never hardcoded in this file.
        let credentialsBlock = """
        let env = ProcessInfo.processInfo.environment
        let apiKey   = env["TESTPILOT_API_KEY"] ?? ""
        let username: String? = env["TESTPILOT_USERNAME"].flatMap { $0.isEmpty ? nil : $0 }
        let password: String? = env["TESTPILOT_PASSWORD"].flatMap { $0.isEmpty ? nil : $0 }
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
\(credentialsBlock)
        let config = ConfigBuilder()
            .provider(provider: provider)
            .apiKey(key: apiKey)
            .maxSteps(steps: \(maxSteps))
            .language(lang: "\(langEsc)")
            .build()
        analyst = TestAnalystIOS(config: config)
    }

    func testAnalyze() async throws {
        let _ = try await analyst.run(
            objective: "\(objEsc)",
            xcApp: xcApp,
            username: username,
            password: password
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
\(credentialsBlock)
        let config = ConfigBuilder()
            .provider(provider: provider)
            .apiKey(key: apiKey)
            .maxSteps(steps: \(maxSteps))
            .language(lang: "\(langEsc)")
            .build()
        analyst = AnalystIOS(config: config)
    }

    func testAnalyze() async throws {
        let _ = try await analyst.run(
            objective: "\(objEsc)",
            xcApp: xcApp,
            username: username,
            password: password
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
            do { try proc.run() } catch {
                proc.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
