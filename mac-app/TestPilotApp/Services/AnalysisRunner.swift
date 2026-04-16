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
    private var isCapturingReport = false
    private var reportLines: [String] = []

    func run(config: RunConfig, settings: SettingsStore) {
        guard case .idle = state else { return }

        if settings.apiKey.isEmpty {
            state = .failed(error: "API key not set — open Settings and enter your API key")
            return
        }

        let folder = NSString(string: settings.reportFolder.isEmpty ? "~/Desktop" : settings.reportFolder)
            .expandingTildeInPath
        let outputPath = (folder as NSString).appendingPathComponent("report.html")
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
        isCapturingReport = false
        reportLines = []
        state = .idle
    }

    func reset() {
        process?.terminate()
        process = nil
        analyzeSteps = []
        isCapturingReport = false
        reportLines = []
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
            DispatchQueue.main.async {
                self?.processStdoutChunk(text, outputPath: outputPath)
            }
        }

        p.terminationHandler = { [weak self] proc in
            // Drain any remaining stdout before nil-ing the handler so the last
            // lines (including TESTPILOT_REPORT_PATH=) are not lost.
            let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
            stdout.fileHandleForReading.readabilityHandler = nil
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let lastStderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                    self?.processStdoutChunk(text, outputPath: outputPath)
                }
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

    /// Processes a chunk of raw xcodebuild stdout. Must be called on the main actor.
    /// Handles inline HTML capture (REPORT_START/END) and all TESTPILOT_ markers.
    private func processStdoutChunk(_ text: String, outputPath: String) {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // ── Inline HTML capture (physical device: report lives on-device, not Mac) ──
            if line.contains("TESTPILOT_REPORT_START") {
                isCapturingReport = true
                reportLines = []
                continue
            }
            if line.contains("TESTPILOT_REPORT_END") {
                isCapturingReport = false
                let html = reportLines.joined(separator: "\n")
                if !html.isEmpty, let data = html.data(using: .utf8) {
                    try? data.write(to: URL(fileURLWithPath: outputPath))
                    lastReportPath = outputPath
                }
                reportLines = []
                continue
            }
            if isCapturingReport {
                reportLines.append(rawLine)
                continue
            }

            guard !line.isEmpty else { continue }
            lastStdoutLine = line

            // ── TESTPILOT markers ──
            if let r = line.range(of: "TESTPILOT_STEP: ") {
                let msg = String(line[r.upperBound...])
                let cached = msg.hasPrefix("(cached)")
                let raw    = cached ? String(msg.dropFirst("(cached) ".count)) : msg
                let clean  = beautify(raw)
                let step   = TestStep(message: clean, cached: cached)
                withAnimation(.easeInOut(duration: 0.4)) {
                    switch state {
                    case .testRunning(let steps): state = .testRunning(steps: steps + [step])
                    case .running:
                        analyzeSteps.append(step)
                        state = .running(statusLine: clean)
                    default: break
                    }
                }
            } else if let r = line.range(of: "TESTPILOT_RESULT: ") {
                let payload = String(line[r.upperBound...])
                let steps: [TestStep]
                if case .testRunning(let s) = state { steps = s } else { steps = [] }
                if payload.hasPrefix("PASS ") {
                    state = .testPassed(reason: String(payload.dropFirst("PASS ".count)), steps: steps)
                } else if payload.hasPrefix("FAIL ") {
                    state = .testFailed(reason: String(payload.dropFirst("FAIL ".count)), steps: steps)
                }
            } else if let r = line.range(of: "TESTPILOT_REPORT_PATH=") {
                // Only use this path if we haven't already written the report locally
                // (i.e., the inline capture didn't run, which means it's a simulator).
                let emittedPath = String(line[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if lastReportPath.isEmpty {
                    lastReportPath = emittedPath
                }
            }
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

    // MARK: - Message cleanup

    private func beautify(_ message: String) -> String {
        var s = message

        func replace(_ pattern: String, with replacement: String) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
        }

        replace(#"(?i)\btouch\s*\([^)]*\)"#,              with: "Tap")  // touch(...) → Tap
        replace(#"\(\s*\d+\.?\d*\s*,\s*\d+\.?\d*\s*\)"#, with: "")     // (x, y) coordinates
        replace(#"~?/[\w\-._/]+"#,                         with: "")     // file paths

        s = s.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return s.isEmpty ? message : s
    }
}
