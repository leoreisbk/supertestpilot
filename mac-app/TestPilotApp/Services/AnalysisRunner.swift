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
    private var lastReportPath: String = ""

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
                        await MainActor.run { state = .failed(error: IOSRunnerError.xcodebuildNotFound.localizedDescription) }
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

    func cancel() {
        process?.terminate()
        process = nil
        analyzeSteps = []
        state = .idle
    }

    func reset() {
        process?.terminate()
        process = nil
        analyzeSteps = []
        state = .idle
    }

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

    func saveSession() {
        guard case .webLoginPending = state else { return }
        if let stdin = process?.standardInput as? Pipe {
            stdin.fileHandleForWriting.write(Data([10])) // "\n"
        } else {
            state = .idle
        }
    }

    // MARK: - Private

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
}
