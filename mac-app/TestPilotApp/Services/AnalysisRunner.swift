import Foundation
import AppKit
import Observation
import SwiftUI

struct TestStep: Equatable {
    let message: String
    let cached: Bool
}

enum AnalysisState: Equatable {
    case idle
    case running(statusLine: String)
    case testRunning(steps: [TestStep])
    case completed(reportPath: String)
    case testPassed(reason: String, steps: [TestStep])
    case testFailed(reason: String, steps: [TestStep])
    case failed(error: String)
    case webLoginPending
}

@MainActor
@Observable
final class AnalysisRunner {
    private(set) var state: AnalysisState = .idle
    private(set) var analyzeSteps: [TestStep] = []
    private var process: Process?
    private var lastStdoutLine: String = ""

    func run(config: RunConfig, settings: SettingsStore) {
        guard case .idle = state else { return }

        if settings.apiKey.isEmpty {
            state = .failed(error: "API key not set — open Settings and enter your API key")
            return
        }

        let scriptURL: URL
        if !settings.scriptPath.isEmpty {
            let expanded = NSString(string: settings.scriptPath).expandingTildeInPath
            scriptURL = URL(fileURLWithPath: expanded)
        } else if let bundled = Bundle.main.url(forResource: "testpilot", withExtension: nil) {
            scriptURL = bundled
        } else {
            state = .failed(error: "testpilot script not found — set the script path in Settings")
            return
        }

        let outputPath = NSString(string: config.outputPath).expandingTildeInPath

        var args: [String] = [
            config.mode.rawValue,
            "--platform",  config.platform.rawValue,
            "--objective", config.objective,
            "--lang",      config.language.rawValue,
            "--max-steps", "\(config.maxSteps)",
        ]

        if config.platform == .web {
            args += ["--url", config.url]
        } else {
            args += ["--app", config.appName]
            if let device = config.selectedDevice, device.isPhysical {
                args += ["--device", device.id]
                if !settings.teamId.isEmpty {
                    args += ["--team-id", settings.teamId]
                }
            }
        }

        if !config.username.isEmpty { args += ["--username", config.username] }
        if !config.password.isEmpty { args += ["--password", config.password] }

        if config.mode == .analyze {
            args += ["--output", outputPath]
        }

        let provider = config.providerOverride ?? settings.provider
        args += ["--provider", provider.rawValue]

        var env = ProcessInfo.processInfo.environment
        // Augment PATH with Homebrew and common tool locations that are present in
        // a developer's shell but absent from the minimal launchd environment.
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin",
                          "/usr/local/bin", "/usr/local/sbin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
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

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else { return }

            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lastStdoutLine = line

                    if line.hasPrefix("TESTPILOT_STEP: ") {
                        let msg = String(line.dropFirst("TESTPILOT_STEP: ".count))
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
                            default:
                                break
                            }
                        }
                    } else if line.hasPrefix("TESTPILOT_RESULT: ") {
                        let payload = String(line.dropFirst("TESTPILOT_RESULT: ".count))
                        let steps: [TestStep]
                        if case .testRunning(let s) = self.state { steps = s } else { steps = [] }
                        if payload.hasPrefix("PASS ") {
                            let reason = String(payload.dropFirst("PASS ".count))
                            self.state = .testPassed(reason: reason, steps: steps)
                        } else if payload.hasPrefix("FAIL ") {
                            let reason = String(payload.dropFirst("FAIL ".count))
                            self.state = .testFailed(reason: reason, steps: steps)
                        }
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
                        self.state = .completed(reportPath: outputPath)
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
                default:
                    break
                }
            }
        }

        lastStdoutLine = ""
        analyzeSteps = []
        if config.mode == .test {
            state = .testRunning(steps: [])
        } else {
            state = .running(statusLine: "Starting analysis…")
        }
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
        analyzeSteps = []
        state = .idle
    }

    func reset() {
        analyzeSteps = []
        state = .idle
    }

    func webLogin(config: RunConfig, settings: SettingsStore) {
        guard case .idle = state else { return }

        let scriptURL: URL
        if !settings.scriptPath.isEmpty {
            let expanded = NSString(string: settings.scriptPath).expandingTildeInPath
            scriptURL = URL(fileURLWithPath: expanded)
        } else if let bundled = Bundle.main.url(forResource: "testpilot", withExtension: nil) {
            scriptURL = bundled
        } else {
            state = .failed(error: "testpilot script not found — set the script path in Settings")
            return
        }

        var args: [String] = ["web-login", "--url", config.url]
        let provider = config.providerOverride ?? settings.provider
        args += ["--provider", provider.rawValue]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin",
                          "/usr/local/bin", "/usr/local/sbin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
        env["TESTPILOT_API_KEY"]  = settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider.rawValue

        let p = Process()
        p.executableURL = scriptURL
        p.arguments = args
        p.environment = env

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

        do {
            try p.run()
        } catch {
            state = .failed(error: error.localizedDescription)
        }
    }

    func saveSession() {
        guard case .webLoginPending = state else { return }
        if let stdin = process?.standardInput as? Pipe {
            stdin.fileHandleForWriting.write(Data([10])) // "\n"
        } else {
            state = .idle
        }
    }
}
